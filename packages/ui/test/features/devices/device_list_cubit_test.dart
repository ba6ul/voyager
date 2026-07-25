import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_state.dart';

/// In-memory stand-in for the daemon, in the same spirit as
/// packages/core's FakeAdbServer and packages/daemon's MockScrcpyLauncher.
class FakeDeviceRepository implements DeviceRepository {
  final connectedController = StreamController<bool>.broadcast();
  final devicesController = StreamController<List<Device>>.broadcast();
  final deviceReadyController = StreamController<String>.broadcast();
  final wirelessStatusController = StreamController<StatusEvent>.broadcast();
  final handoffStatusController = StreamController<StatusEvent>.broadcast();

  final List<String> playedSerials = [];
  final List<String> stoppedSerials = [];
  final List<String> wirelessSerials = [];
  final List<String> handoffSerials = [];
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

  @override
  Future<bool> launch(String serial) async {
    playedSerials.add(serial);
    return true;
  }

  @override
  Future<void> stop(String serial) async => stoppedSerials.add(serial);

  @override
  Future<void> goWireless(String serial) async => wirelessSerials.add(serial);

  @override
  Future<void> handoff(String serial) async => handoffSerials.add(serial);

  @override
  Future<void> usbMode(String serial) async {}

  @override
  void dispose() => disposed = true;
}

void main() {
  late FakeDeviceRepository repository;

  setUp(() {
    repository = FakeDeviceRepository();
  });

  test('connects to the repository on creation', () {
    DeviceListCubit(repository);
    expect(repository.connectCalled, isTrue);
  });

  test('reflects the repository connection state', () async {
    final cubit = DeviceListCubit(repository);

    repository.connectedController.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.connection, DaemonConnection.connected);

    repository.connectedController.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.connection, DaemonConnection.unreachable);
  });

  test('updates the device list from the repository stream', () async {
    final cubit = DeviceListCubit(repository);
    const device =
        Device(serial: 'ABC123', state: DeviceState.device, mirroring: false);

    repository.devicesController.add([device]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.devices, [device]);
  });

  test('calls onDeviceReady when a device becomes ready', () async {
    String? readySerial;
    DeviceListCubit(repository, onDeviceReady: (serial) => readySerial = serial);

    repository.deviceReadyController.add('ABC123');
    await Future<void>.delayed(Duration.zero);

    expect(readySerial, 'ABC123');
  });

  test('records wireless and handoff progress as status messages', () async {
    final cubit = DeviceListCubit(repository);

    repository.wirelessStatusController
        .add(const StatusEvent(serial: 'ABC123', stage: 'connecting'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.statusMessages['ABC123'], contains('connecting'));

    repository.handoffStatusController.add(const StatusEvent(
      serial: 'ABC123',
      stage: 'complete',
      detail: '1.2.3.4:5555',
    ));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.statusMessages['ABC123'], contains('complete'));
    expect(cubit.state.statusMessages['ABC123'], contains('1.2.3.4:5555'));
  });

  test('play/stop/goWireless/handoff delegate to the repository', () async {
    final cubit = DeviceListCubit(repository);

    await cubit.play('ABC123');
    await cubit.stop('ABC123');
    await cubit.goWireless('ABC123');
    await cubit.handoff('ABC123');

    expect(repository.playedSerials, ['ABC123']);
    expect(repository.stoppedSerials, ['ABC123']);
    expect(repository.wirelessSerials, ['ABC123']);
    expect(repository.handoffSerials, ['ABC123']);
  });

  test('disposes the repository when closed', () async {
    final cubit = DeviceListCubit(repository);
    await cubit.close();
    expect(repository.disposed, isTrue);
  });
}
