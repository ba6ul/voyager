import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/progress_text.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list.dart';

import 'fake_device_repository.dart';

const _serial = 'R58M12ABCDE';
const _phone = Device(
  serial: _serial,
  state: DeviceState.device,
  model: 'Pixel 7',
  mirroring: false,
  transport: DeviceTransport.usb,
);

/// When a Go Wireless / Handoff progress line goes away, and what the row
/// shows while the user has to act.
void main() {
  group('a progress line', () {
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

    Future<void> wireless(String stage, [String? detail]) async {
      repository.wirelessStatusController
          .add(StatusEvent(serial: _serial, stage: stage, detail: detail));
      await flush();
    }

    Future<void> devices(List<Device> list) async {
      repository.devicesController.add(list);
      await flush();
    }

    test('that has finished goes when its device leaves the list, and does '
        'not come back with it', () async {
      await wireless('failed', 'timed out after 3 minutes');

      await devices([]);
      expect(cubit.state.statusMessages, isEmpty);

      await devices([_phone]);
      expect(cubit.state.statusMessages, isEmpty);
    });

    test('of a flow still running survives the device dropping out briefly',
        () async {
      // adb tcpip restarts the phone's adb, which drops the USB entry for a
      // moment while Go Wireless is still waiting for the hotspot.
      await wireless('waitingForHotspot');

      await devices([]);
      await devices([_phone]);

      expect(cubit.state.statusMessages[_serial]?.text,
          contains(hotspotInstruction));
    });

    test('is replaced by the next progress for the device', () async {
      await wireless('waitingForHotspot');
      await wireless('connected', '192.168.43.1:5555');

      expect(cubit.state.statusMessages[_serial]?.text,
          startsWith('Connected wirelessly at 192.168.43.1:5555'));
      expect(cubit.state.statusMessages[_serial]?.finished, isTrue);
    });

    test('of another device is left alone', () async {
      repository.wirelessStatusController.add(const StatusEvent(
          serial: 'OTHER', stage: 'failed', detail: 'no answer'));
      await flush();
      await devices([
        _phone,
        const Device(
            serial: 'OTHER', state: DeviceState.device, mirroring: false),
      ]);

      await devices([_phone]);

      expect(cubit.state.statusMessages.containsKey('OTHER'), isFalse);
    });
  });

  testWidgets('the row tells the user to join the hotspot while Go Wireless '
      'waits', (tester) async {
    final repository = FakeDeviceRepository();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(value: cubit, child: const DeviceList()),
    ));
    repository.connectedController.add(true);
    repository.devicesController.add([_phone]);
    await tester.pumpAndSettle();

    repository.wirelessStatusController
        .add(const StatusEvent(serial: _serial, stage: 'waitingForHotspot'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Turn on the phone's hotspot and connect this "
        'PC to it'), findsOneWidget);
    expect(find.textContaining('waitingForHotspot'), findsNothing);
  });
}
