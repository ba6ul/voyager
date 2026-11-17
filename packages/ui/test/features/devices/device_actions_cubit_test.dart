import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_state.dart';

import 'fake_device_repository.dart';

const _serial = 'R58M12ABCDE';
const _phone = Device(
  serial: _serial,
  state: DeviceState.device,
  model: 'Pixel 7',
  mirroring: false,
);

/// #58: Play, Stop, Go Wireless and Handoff are tracked while in flight and
/// report what went wrong, the way Try Now already did.
void main() {
  late FakeDeviceRepository repository;
  late DeviceListCubit cubit;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    repository = FakeDeviceRepository();
    cubit = DeviceListCubit(repository);
    repository.devicesController.add([_phone]);
    await flush();
  });

  tearDown(() => cubit.close());

  final actions = <DeviceAction, Future<void> Function(DeviceListCubit)>{
    DeviceAction.play: (c) => c.play(_serial),
    DeviceAction.stop: (c) => c.stop(_serial),
    DeviceAction.goWireless: (c) => c.goWireless(_serial),
    DeviceAction.handoff: (c) => c.handoff(_serial),
  };

  group('in flight', () {
    actions.forEach((action, run) {
      test('${action.name} is in progress until the daemon answers, then '
          'leaves nothing when it worked', () async {
        repository.commandGate = Completer<void>();

        final done = run(cubit);
        await flush();
        expect(cubit.state.actions[_serial],
            DeviceActionStatus.inProgress(action));

        repository.commandGate!.complete();
        await done;
        expect(cubit.state.actions, isEmpty);
      });
    });

    test('a second action for the same device is not sent meanwhile',
        () async {
      repository.commandGate = Completer<void>();

      final play = cubit.play(_serial);
      await flush();
      await cubit.play(_serial);
      await cubit.stop(_serial);
      await cubit.goWireless(_serial);
      repository.commandGate!.complete();
      await play;

      expect(repository.playedSerials, [_serial]);
      expect(repository.stoppedSerials, isEmpty);
      expect(repository.wirelessSerials, isEmpty);
    });

    test('another device is not held up', () async {
      repository.commandGate = Completer<void>();

      final first = cubit.play(_serial);
      final second = cubit.play('OTHER');
      repository.commandGate!.complete();
      await Future.wait([first, second]);

      expect(repository.playedSerials, [_serial, 'OTHER']);
    });

    test('closing the cubit meanwhile does not throw', () async {
      repository.commandGate = Completer<void>();

      final play = cubit.play(_serial);
      await flush();
      await cubit.close();
      repository.commandGate!.complete();

      await expectLater(play, completes);
    });
  });

  group('outcome', () {
    test('Play on a phone that is already mirroring says so', () async {
      repository.launchOutcome = LaunchOutcome.alreadyRunning;

      await cubit.play(_serial);

      expect(cubit.state.actions[_serial],
          const DeviceActionStatus.finished(
              DeviceAction.play, 'Already mirroring.'));
    });

    const failures = {
      DeviceAction.play: 'Could not start mirroring',
      DeviceAction.stop: 'Could not stop mirroring',
      DeviceAction.goWireless: 'Could not start Go Wireless',
      DeviceAction.handoff: 'Could not start the handoff',
    };
    actions.forEach((action, run) {
      test('${action.name} that fails says why, and does not throw',
          () async {
        repository.commandError =
            const DaemonCommandException(DaemonCommandFailure.timedOut);

        await expectLater(run(cubit), completes);

        expect(
          cubit.state.actions[_serial]?.message,
          '${failures[action]}: the background service did not answer in '
          'time',
        );
        expect(cubit.state.actions[_serial]?.inProgress, isFalse);
      });
    });

    test('an unexpected error is still caught and shown', () async {
      repository.commandError = StateError('something else');

      await expectLater(cubit.stop(_serial), completes);

      expect(cubit.state.actions[_serial]?.message,
          contains('Could not stop mirroring'));
    });
  });

  group('an outcome line is cleared', () {
    Future<void> failPlay() async {
      repository.commandError =
          const DaemonCommandException(DaemonCommandFailure.disconnected);
      await cubit.play(_serial);
      repository.commandError = null;
      expect(cubit.state.actions[_serial], isNotNull);
    }

    test('by the next action', () async {
      await failPlay();

      await cubit.play(_serial);

      expect(cubit.state.actions, isEmpty);
    });

    test('by a newer wireless or handoff status for the device', () async {
      await failPlay();

      repository.wirelessStatusController
          .add(const StatusEvent(serial: _serial, stage: 'connecting'));
      await flush();

      expect(cubit.state.actions, isEmpty);
      expect(cubit.state.statusMessages[_serial]?.text,
          startsWith('Go Wireless:'));
    });

    test('when the device leaves the list', () async {
      await failPlay();

      repository.devicesController.add([]);
      await flush();

      expect(cubit.state.actions, isEmpty);
    });

    test('and not kept for a device that left while it was in flight',
        () async {
      repository.commandGate = Completer<void>();
      repository.commandError =
          const DaemonCommandException(DaemonCommandFailure.disconnected);

      final play = cubit.play(_serial);
      await flush();
      repository.devicesController.add([]);
      await flush();
      expect(cubit.state.actions[_serial]?.inProgress, isTrue,
          reason: 'still in flight, so still tracked');
      repository.commandGate!.complete();
      await play;

      expect(cubit.state.actions, isEmpty);
    });
  });

  test('a status event does not clear an action still in flight', () async {
    repository.commandGate = Completer<void>();

    final goWireless = cubit.goWireless(_serial);
    await flush();
    repository.wirelessStatusController
        .add(const StatusEvent(serial: _serial, stage: 'readingWifiIp'));
    await flush();

    expect(cubit.state.actions[_serial]?.inProgress, isTrue);
    repository.commandGate!.complete();
    await goWireless;
  });
}
