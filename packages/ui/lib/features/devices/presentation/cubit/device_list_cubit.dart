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
      _repository.devices.listen((devices) => emit(
            state.copyWith(devices: devices),
          )),
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
    emit(state.copyWith(statusMessages: messages));
  }

  Future<bool> play(String serial) => _repository.launch(serial);
  Future<void> stop(String serial) => _repository.stop(serial);
  Future<void> goWireless(String serial) => _repository.goWireless(serial);
  Future<void> handoff(String serial) => _repository.handoff(serial);

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
