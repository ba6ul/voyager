import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list_popup.dart';

import 'fake_device_repository.dart';

Device _phone({required bool mirroring}) => Device(
      serial: 'R58M12ABCDE',
      state: DeviceState.device,
      model: 'Pixel 7',
      mirroring: mirroring,
    );

/// #56: the Play/Stop button follows `mirroring` in the daemon's device
/// snapshots, in both directions, and nothing else.
void main() {
  late FakeDeviceRepository repository;

  // Created inside the test body (the widget test's fake-async zone), like
  // device_list_popup_test.dart, so tester.pump() flushes stream events.
  Future<void> showPopup(WidgetTester tester) async {
    repository = FakeDeviceRepository();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(value: cubit, child: const DeviceListPopup()),
    ));
    repository.connectedController.add(true);
    await tester.pump();
  }

  Future<void> snapshot(WidgetTester tester, {required bool mirroring}) async {
    repository.devicesController.add([_phone(mirroring: mirroring)]);
    // The event reaches the cubit, then the rebuild: not always in one frame.
    await tester.pumpAndSettle();
  }

  testWidgets('switches from Play to Stop and back as snapshots arrive',
      (tester) async {
    await showPopup(tester);

    await snapshot(tester, mirroring: false);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);

    await snapshot(tester, mirroring: true);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Play'), findsNothing);

    await snapshot(tester, mirroring: false);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('Play asks the daemon and waits for its snapshot to switch',
      (tester) async {
    await showPopup(tester);
    await snapshot(tester, mirroring: false);

    await tester.tap(find.text('Play'));
    await tester.pump();

    expect(repository.playedSerials, ['R58M12ABCDE']);
    // The UI keeps no mirroring state of its own: until the daemon says the
    // phone is mirroring, the button stays as it was.
    expect(find.text('Play'), findsOneWidget);

    await snapshot(tester, mirroring: true);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('Stop asks the daemon and waits for its snapshot to switch',
      (tester) async {
    await showPopup(tester);
    await snapshot(tester, mirroring: true);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(repository.stoppedSerials, ['R58M12ABCDE']);
    expect(find.text('Stop'), findsOneWidget);

    await snapshot(tester, mirroring: false);
    expect(find.text('Play'), findsOneWidget);
  });
}
