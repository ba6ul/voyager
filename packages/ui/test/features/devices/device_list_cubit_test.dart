import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/cached_device.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_state.dart';

import 'fake_device_repository.dart';

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

  test('updates known devices from the repository stream', () async {
    final cubit = DeviceListCubit(repository);
    const cached = CachedDevice(
      usbSerial: 'ABC123',
      model: 'Pixel 7',
      lastIp: '192.168.1.42',
      lastPort: 5555,
    );

    repository.knownDevicesController.add([cached]);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.knownDevices, [cached]);
  });

  test('retryReconnect delegates to the repository', () async {
    final cubit = DeviceListCubit(repository);

    await cubit.retryReconnect('ABC123');

    expect(repository.retryReconnectSerials, ['ABC123']);
  });

  group('retryReconnect feedback', () {
    test('is in progress until the daemon answers, then shows the outcome',
        () async {
      final cubit = DeviceListCubit(repository);
      repository.retryGate = Completer<void>();
      repository.retryResult = const RetryResult(RetryOutcome.unreachable,
          address: '192.168.1.42:5555');

      final pending = cubit.retryReconnect('ABC123');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.retries['ABC123']?.inProgress, isTrue);
      expect(cubit.state.retries['ABC123']?.message, isNull);

      repository.retryGate!.complete();
      await pending;

      final status = cubit.state.retries['ABC123']!;
      expect(status.inProgress, isFalse);
      expect(status.message, contains('192.168.1.42:5555'));
      expect(status.message, contains('USB'));
    });

    test('says so when the phone is already connected', () async {
      final cubit = DeviceListCubit(repository);
      repository.retryResult = const RetryResult(RetryOutcome.skipped);

      await cubit.retryReconnect('ABC123');

      expect(cubit.state.retries['ABC123']?.message, contains('already connected'));
    });

    test('reports a successful reconnect as waiting for the phone', () async {
      final cubit = DeviceListCubit(repository);

      await cubit.retryReconnect('ABC123');

      final status = cubit.state.retries['ABC123']!;
      expect(status.inProgress, isFalse);
      expect(status.message, contains('Connected to 192.168.1.42:5555'));
    });

    test('shows the failure when the daemon cannot be asked', () async {
      final cubit = DeviceListCubit(repository);
      repository.retryError = StateError('not connected to the daemon');

      await cubit.retryReconnect('ABC123');

      final status = cubit.state.retries['ABC123']!;
      expect(status.inProgress, isFalse);
      expect(status.message, startsWith('Could not retry'));
      expect(status.message, contains('not connected to the daemon'));
    });

    test('ignores a second tap while one retry is in flight', () async {
      final cubit = DeviceListCubit(repository);
      repository.retryGate = Completer<void>();

      final first = cubit.retryReconnect('ABC123');
      await Future<void>.delayed(Duration.zero);
      await cubit.retryReconnect('ABC123');
      repository.retryGate!.complete();
      await first;

      expect(repository.retryReconnectSerials, ['ABC123']);
    });

    test('keeps retries of different devices independent', () async {
      final cubit = DeviceListCubit(repository);
      repository.retryGate = Completer<void>();

      final a = cubit.retryReconnect('AAA');
      await Future<void>.delayed(Duration.zero);
      final b = cubit.retryReconnect('BBB');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.retries.keys, containsAll(['AAA', 'BBB']));

      repository.retryGate!.complete();
      await Future.wait([a, b]);
      expect(repository.retryReconnectSerials, ['AAA', 'BBB']);
    });

    test('does not throw if the cubit is closed while a retry is in flight',
        () async {
      final cubit = DeviceListCubit(repository);
      repository.retryGate = Completer<void>();

      final pending = cubit.retryReconnect('ABC123');
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      repository.retryGate!.complete();

      await expectLater(pending, completes);
    });
  });

  test('disposes the repository when closed', () async {
    final cubit = DeviceListCubit(repository);
    await cubit.close();
    expect(repository.disposed, isTrue);
  });

  group('DeviceListState.pendingReconnect', () {
    const cached = CachedDevice(
      usbSerial: 'ABC123',
      model: 'Pixel 7',
      lastIp: '192.168.1.42',
      lastPort: 5555,
    );

    test('includes a cached device not present in the live device list', () {
      const state = DeviceListState(knownDevices: [cached]);
      expect(state.pendingReconnect, [cached]);
    });

    test('excludes a cached device already live under its network serial', () {
      final state = DeviceListState(
        knownDevices: const [cached],
        devices: [
          Device(
            serial: cached.networkSerial,
            state: DeviceState.device,
            mirroring: true,
          ),
        ],
      );
      expect(state.pendingReconnect, isEmpty);
    });

    test('excludes a cached device that is live over USB', () {
      final state = DeviceListState(
        knownDevices: const [cached],
        devices: const [
          Device(
              serial: 'ABC123', state: DeviceState.device, mirroring: false),
        ],
      );
      expect(state.pendingReconnect, isEmpty);
    });

    test('excludes a cached device that is live as a wireless-debugging serial',
        () {
      // Regression: the phone showed up twice, once as the live device and
      // once as "previously connected" with a Try Now button.
      final state = DeviceListState(
        knownDevices: const [cached],
        devices: const [
          Device(
            serial: 'adb-ABC123-HvLNB1._adb-tls-connect._tcp',
            state: DeviceState.device,
            mirroring: false,
          ),
        ],
      );
      expect(state.pendingReconnect, isEmpty);
    });

    test('keeps a cached device pending when only a different phone is live',
        () {
      final state = DeviceListState(
        knownDevices: const [cached],
        devices: const [
          Device(
              serial: 'R58M12ABCDE', state: DeviceState.device, mirroring: true),
        ],
      );
      expect(state.pendingReconnect, [cached]);
    });
  });
}
