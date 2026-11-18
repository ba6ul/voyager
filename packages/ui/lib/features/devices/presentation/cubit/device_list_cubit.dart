import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/device_repository.dart';
import '../../domain/entities/device.dart';
import '../progress_text.dart';
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
      _repository.devices.listen((devices) {
        bool listed(String serial) => devices.any((d) => d.serial == serial);
        emit(state.copyWith(
          devices: devices,
          // A device that left takes its finished action status and progress
          // line with it, so neither comes back if the serial reappears.
          actions: {
            for (final entry in state.actions.entries)
              if (entry.value.inProgress || listed(entry.key))
                entry.key: entry.value,
          },
          statusMessages: {
            for (final entry in state.statusMessages.entries)
              if (!entry.value.finished || listed(entry.key))
                entry.key: entry.value,
          },
        ));
      }),
      _repository.deviceReadySerials.listen(_onDeviceReady),
      _repository.wirelessStatus
          .listen((e) => _onStatus(ProgressKind.wireless, e)),
      _repository.handoffStatus
          .listen((e) => _onStatus(ProgressKind.handoff, e)),
      _repository.knownDevices.listen((knownDevices) => emit(
            state.copyWith(knownDevices: knownDevices),
          )),
    ];
    unawaited(_repository.connect());
  }

  final DeviceRepository _repository;

  /// Called with a serial when a phone is newly plugged in over USB, so the
  /// app can bring the popup window to front. Not called for wireless
  /// reconnects, emulators, or a serial that already became ready earlier in
  /// this session (a flapping cable): those are not something the user just
  /// did, and must not take focus from what they are doing.
  final void Function(String serial)? onDeviceReady;

  late final List<StreamSubscription<void>> _subscriptions;

  /// Serials that have become ready at least once in this session.
  final Set<String> _seenReady = {};

  void _onDeviceReady(String serial) {
    // add() is false for a serial seen before.
    if (!_seenReady.add(serial)) return;
    // The device list may not have this serial yet; the serial's shape is the
    // fallback Device.transport itself uses.
    final listed = state.devices.where((d) => d.serial == serial);
    final transport =
        listed.isEmpty ? DeviceTransport.of(serial) : listed.first.transport;
    if (transport == DeviceTransport.usb) onDeviceReady?.call(serial);
  }

  void _onStatus(ProgressKind kind, StatusEvent event) {
    final messages = Map<String, ProgressLine>.from(state.statusMessages);
    messages[event.serial] = ProgressLine(
      describeProgress(kind, event),
      finished: isFinalStage(event.stage),
    );
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

  /// Drops a phone that was connected over the network (`adb disconnect`).
  /// The daemon refuses it for anything but USB and network devices; the row
  /// only offers it for a network one. The row leaves the list when adb
  /// reports the device gone.
  Future<void> disconnect(String serial) =>
      _runAction(serial, DeviceAction.disconnect, () async {
        await _repository.usbMode(serial);
        return null;
      });

  // The commands below are for the console: they report failure by throwing
  // (a DaemonCommandException) instead of showing it on a device row.

  /// Switches [serial] back to USB-only (disconnects a network address).
  Future<void> usbMode(String serial) => _repository.usbMode(serial);

  /// Closes every mirror window.
  Future<void> stopAll() => _repository.stopAll();

  /// The daemon's config.json contents.
  Future<Map<String, dynamic>> daemonConfig() => _repository.config();

  /// Shuts the daemon down.
  Future<void> quitDaemon() => _repository.quit();

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
        DeviceAction.disconnect => 'Could not disconnect',
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
        return 'No answer from $where. The phone may have restarted, changed '
            'network, or no longer trusts this PC. Pair it again with PAIR, '
            'or plug it in with USB and use Go Wireless.';
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
