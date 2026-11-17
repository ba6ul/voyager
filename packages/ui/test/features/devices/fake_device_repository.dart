import 'dart:async';

import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/cached_device.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';

/// In-memory stand-in for the daemon, in the same spirit as
/// packages/core's FakeAdbServer and packages/daemon's MockScrcpyLauncher.
class FakeDeviceRepository implements DeviceRepository {
  final connectedController = StreamController<bool>.broadcast();
  final devicesController = StreamController<List<Device>>.broadcast();
  final deviceReadyController = StreamController<String>.broadcast();
  final wirelessStatusController = StreamController<StatusEvent>.broadcast();
  final handoffStatusController = StreamController<StatusEvent>.broadcast();
  final knownDevicesController = StreamController<List<CachedDevice>>.broadcast();

  final List<String> playedSerials = [];
  final List<String> stoppedSerials = [];
  final List<String> wirelessSerials = [];
  final List<String> handoffSerials = [];
  final List<String> usbModeSerials = [];
  final List<String> retryReconnectSerials = [];
  bool connectCalled = false;
  bool disposed = false;

  @override
  Future<void> connect() async => connectCalled = true;

  @override
  Stream<bool> get connected => connectedController.stream;

  @override
  Stream<List<Device>> get devices => devicesController.stream;

  @override
  Stream<String> get deviceReadySerials => deviceReadyController.stream;

  @override
  Stream<StatusEvent> get wirelessStatus => wirelessStatusController.stream;

  @override
  Stream<StatusEvent> get handoffStatus => handoffStatusController.stream;

  /// What the next launch returns, unless [commandError] is set.
  LaunchOutcome launchOutcome = LaunchOutcome.started;

  /// Thrown by launch, stop, goWireless and handoff when set, like the real
  /// repository's DaemonCommandException.
  Object? commandError;

  /// When set, launch, stop, goWireless and handoff wait for it, so a test
  /// can look at the in-flight state.
  Completer<void>? commandGate;

  Future<void> _command(List<String> calls, String serial) async {
    calls.add(serial);
    await commandGate?.future;
    if (commandError != null) throw commandError!;
  }

  @override
  Future<LaunchOutcome> launch(String serial) async {
    await _command(playedSerials, serial);
    return launchOutcome;
  }

  @override
  Future<void> stop(String serial) => _command(stoppedSerials, serial);

  @override
  Future<void> goWireless(String serial) => _command(wirelessSerials, serial);

  @override
  Future<void> handoff(String serial) => _command(handoffSerials, serial);

  @override
  Future<void> usbMode(String serial) => _command(usbModeSerials, serial);

  @override
  Stream<List<CachedDevice>> get knownDevices => knownDevicesController.stream;

  /// What the next retryReconnect returns, unless [retryError] is set.
  RetryResult retryResult = const RetryResult(
    RetryOutcome.reconnected,
    address: '192.168.1.42:5555',
  );
  Object? retryError;

  /// When set, retryReconnect waits for it, so a test can look at the
  /// in-progress state.
  Completer<void>? retryGate;

  @override
  Future<RetryResult> retryReconnect(String usbSerial) async {
    retryReconnectSerials.add(usbSerial);
    await retryGate?.future;
    if (retryError != null) throw retryError!;
    return retryResult;
  }

  @override
  void dispose() => disposed = true;
}
