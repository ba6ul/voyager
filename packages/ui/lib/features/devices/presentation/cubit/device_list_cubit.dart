import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/device_repository.dart';
import 'device_list_state.dart';

class DeviceListCubit extends Cubit<DeviceListState> {
  DeviceListCubit(this._repository, {this.onDeviceReady})
      : super(const DeviceListState()) {
    _subscriptions = [
      _repository.connected.listen((connected) => emit(state.copyWith(
            connection: connected
                ? DaemonConnection.connected
                : DaemonConnection.unreachable,
          ))),
      _repository.devices.listen((devices) => emit(state.copyWith(
            devices: devices,
            // A device that left takes its finished action status with it.
            actions: {
              for (final entry in state.actions.entries)
                if (entry.value.inProgress ||
                    devices.any((d) => d.serial == entry.key))
                  entry.key: entry.value,
            },
          ))),
      _repository.deviceReadySerials.listen((serial) {
        onDeviceReady?.call(serial);
      }),
      _repository.wirelessStatus.listen((e) => _onStatus('wireless', e)),
      _repository.handoffStatus.listen((e) => _onStatus('handoff', e)),
      _repository.knownDevices.listen((knownDevices) => emit(
            state.copyWith(knownDevices: knownDevices),
          )),
    ];
    unawaited(_repository.connect());
  }

  final DeviceRepository _repository;

  /// Called with a device's serial the moment it becomes ready, so the app
  /// can bring the popup window to front.
  final void Function(String serial)? onDeviceReady;

  late final List<StreamSubscription<void>> _subscriptions;

  void _onStatus(String kind, StatusEvent event) {
    final messages = Map<String, String>.from(state.statusMessages);
    messages[event.serial] =
        '$kind: ${event.stage}${event.detail != null ? " (${event.detail})" : ""}';
    // Newer news about the device than a finished action's outcome line.
    final actions = Map<String, DeviceActionStatus>.from(state.actions);
    if (actions[event.serial]?.inProgress == false) actions.remove(event.serial);
    emit(state.copyWith(statusMessages: messages, actions: actions));
  }

  // Play/Stop/Go Wireless/Handoff. Each is tracked in DeviceListState.actions
  // while in flight, and a failure is shown on the row. None of them throws:
  // the row's callbacks do not await them.

  Future<void> play(String serial) => _runAction(serial, DeviceAction.play,
      () async {
        // A start shows as Stop once the daemon's next device list arrives.
        final outcome = await _repository.launch(serial);
        return outcome == LaunchOutcome.alreadyRunning
            ? 'Already mirroring.'
            : null;
      });

  Future<void> stop(String serial) =>
      _runAction(serial, DeviceAction.stop, () async {
        await _repository.stop(serial);
        return null;
      });

  // A request the daemon turns away is not reported here: the daemon sends
  // the reason as a wireless/handoff status event, shown by _onStatus.
  Future<void> goWireless(String serial) =>
      _runAction(serial, DeviceAction.goWireless, () async {
        await _repository.goWireless(serial);
        return null;
      });

  Future<void> handoff(String serial) =>
      _runAction(serial, DeviceAction.handoff, () async {
        await _repository.handoff(serial);
        return null;
      });

  /// Runs [command] for [serial] unless an action for it is already in
  /// flight. [command] returns a message for the row, or null when the
  /// result needs no words.
  Future<void> _runAction(
    String serial,
    DeviceAction action,
    Future<String?> Function() command,
  ) async {
    if (state.actions[serial]?.inProgress ?? false) return;
    _setAction(serial, DeviceActionStatus.inProgress(action));
    String? message;
    try {
      message = await command();
    } catch (e) {
      message = '${_failurePrefix(action)}: $e';
    }
    _setAction(
      serial,
      message == null ? null : DeviceActionStatus.finished(action, message),
    );
  }

  static String _failurePrefix(DeviceAction action) => switch (action) {
        DeviceAction.play => 'Could not start mirroring',
        DeviceAction.stop => 'Could not stop mirroring',
        DeviceAction.goWireless => 'Could not start Go Wireless',
        DeviceAction.handoff => 'Could not start the handoff',
      };

  /// Sets or (with null) clears the action status of [serial]. A finished
  /// status for a device that is no longer listed is not kept.
  void _setAction(String serial, DeviceActionStatus? status) {
    if (isClosed) return;
    final actions = Map<String, DeviceActionStatus>.from(state.actions);
    final listed = state.devices.any((d) => d.serial == serial);
    if (status == null || (!status.inProgress && !listed)) {
      actions.remove(serial);
    } else {
      actions[serial] = status;
    }
    emit(state.copyWith(actions: actions));
  }

  /// "Try Now" for a cached device. Tracks the attempt in [DeviceListState.retries]
  /// so the row can show progress and, afterwards, what happened.
  Future<void> retryReconnect(String usbSerial) async {
    if (state.retries[usbSerial]?.inProgress ?? false) return;
    _setRetry(usbSerial, const RetryStatus.trying());
    try {
      final result = await _repository.retryReconnect(usbSerial);
      _setRetry(usbSerial, RetryStatus.finished(_describe(result)));
    } catch (e) {
      _setRetry(usbSerial, RetryStatus.finished('Could not retry: $e'));
    }
  }

  void _setRetry(String usbSerial, RetryStatus status) {
    if (isClosed) return;
    emit(state.copyWith(retries: {...state.retries, usbSerial: status}));
  }

  String _describe(RetryResult result) {
    final where = result.address ?? 'the saved address';
    switch (result.outcome) {
      case RetryOutcome.reconnected:
        return 'Connected to $where – waiting for the phone to report in…';
      case RetryOutcome.unreachable:
        return 'No answer from $where. If the phone restarted or changed '
            'network, plug it in with USB and use Go Wireless again.';
      case RetryOutcome.skipped:
        return 'Not retried: this phone is already connected, or a wireless '
            'setup is running.';
      case RetryOutcome.requested:
        return 'Retry requested.';
    }
  }

  @override
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _repository.dispose();
    return super.close();
  }
}
