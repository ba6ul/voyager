import 'dart:async';

import 'package:scrcpy_ipc/scrcpy_ipc.dart';

import '../../../core/ipc/ipc_connection.dart';
import '../domain/device_repository.dart';
import '../domain/entities/cached_device.dart';
import '../domain/entities/device.dart';
import 'models/cached_device_model.dart';
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
  Stream<List<CachedDevice>> get knownDevices => _connection.events
      .where((e) => e.event == IpcEvents.knownDevices)
      .map((e) => (e.data['devices'] as List)
          .cast<Map<String, dynamic>>()
          .map(cachedDeviceFromJson)
          .toList());

  /// Sends [cmd] and turns every way it can fail into a
  /// [DaemonCommandException]. Async on purpose: [IpcConnection.send] throws
  /// synchronously when there is no connection, and that must be caught here
  /// too, not escape to the caller.
  Future<IpcResult> _send(String cmd, String serial) async {
    try {
      return await _connection.send(cmd, {'serial': serial});
    } on IpcCommandFailed catch (e) {
      throw DaemonCommandException(
          DaemonCommandFailure.rejected, _firstLine(e.message));
    } on TimeoutException {
      throw const DaemonCommandException(DaemonCommandFailure.timedOut);
    } on StateError {
      // Not connected, or the connection dropped before the reply.
      throw const DaemonCommandException(DaemonCommandFailure.disconnected);
    }
  }

  /// The daemon's error text can be a multi-line exception (e.g. a
  /// ProcessException with the full command); its first line says enough.
  static String _firstLine(String text) => text.trim().split('\n').first.trim();

  @override
  Future<LaunchOutcome> launch(String serial) async {
    final result = await _send(IpcCommands.launch, serial);
    return result.data['alreadyRunning'] == true
        ? LaunchOutcome.alreadyRunning
        : LaunchOutcome.started;
  }

  @override
  Future<void> stop(String serial) => _send(IpcCommands.stop, serial);

  @override
  Future<void> goWireless(String serial) =>
      _send(IpcCommands.goWireless, serial);

  @override
  Future<void> handoff(String serial) => _send(IpcCommands.handoff, serial);

  @override
  Future<void> usbMode(String serial) => _send(IpcCommands.usbMode, serial);

  @override
  Future<RetryResult> retryReconnect(String usbSerial) async {
    final result = await _send(IpcCommands.retryReconnect, usbSerial);
    final outcome = RetryOutcome.values.firstWhere(
      (o) => o.name == result.data['outcome'],
      orElse: () => RetryOutcome.requested,
    );
    return RetryResult(outcome, address: result.data['address'] as String?);
  }

  @override
  void dispose() => _connection.dispose();
}
