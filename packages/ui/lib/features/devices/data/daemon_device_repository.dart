import 'package:scrcpy_ipc/scrcpy_ipc.dart';

import '../../../core/ipc/ipc_connection.dart';
import '../domain/device_repository.dart';
import '../domain/entities/device.dart';
import 'models/device_model.dart';

/// Implements [DeviceRepository] over the daemon's IPC protocol.
class DaemonDeviceRepository implements DeviceRepository {
  DaemonDeviceRepository(this._connection);

  final IpcConnection _connection;

  @override
  Future<void> connect() => _connection.start();

  @override
  Stream<bool> get connected => _connection.connected;

  @override
  Stream<List<Device>> get devices => _connection.events
      .where((e) => e.event == IpcEvents.devices)
      .map((e) => (e.data['devices'] as List)
          .cast<Map<String, dynamic>>()
          .map(deviceFromJson)
          .toList());

  @override
  Stream<String> get deviceReadySerials => _connection.events
      .where((e) => e.event == IpcEvents.deviceReady)
      .map((e) => e.data['serial'] as String);

  @override
  Stream<StatusEvent> get wirelessStatus =>
      _statusStream(IpcEvents.wirelessStatus);

  @override
  Stream<StatusEvent> get handoffStatus =>
      _statusStream(IpcEvents.handoffStatus);

  Stream<StatusEvent> _statusStream(String eventName) => _connection.events
      .where((e) => e.event == eventName)
      .map((e) => StatusEvent(
            serial: e.data['serial'] as String,
            stage: e.data['stage'] as String,
            detail: e.data['detail'] as String?,
          ));

  @override
  Future<bool> launch(String serial) async {
    final result =
        await _connection.send(IpcCommands.launch, {'serial': serial});
    return result.data['launched'] as bool? ?? false;
  }

  @override
  Future<void> stop(String serial) =>
      _connection.send(IpcCommands.stop, {'serial': serial});

  @override
  Future<void> goWireless(String serial) =>
      _connection.send(IpcCommands.goWireless, {'serial': serial});

  @override
  Future<void> handoff(String serial) =>
      _connection.send(IpcCommands.handoff, {'serial': serial});

  @override
  Future<void> usbMode(String serial) =>
      _connection.send(IpcCommands.usbMode, {'serial': serial});

  @override
  void dispose() => _connection.dispose();
}
