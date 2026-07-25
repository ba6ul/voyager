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

  @override
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _repository.dispose();
    return super.close();
  }
}
