import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list_popup.dart';

import 'fake_device_repository.dart';

const _serial = 'R58M12ABCDE';

Device _phone({bool mirroring = false}) => Device(
      serial: _serial,
      state: DeviceState.device,
      model: 'Pixel 7',
      mirroring: mirroring,
      transport: DeviceTransport.usb,
    );

/// #58: what the device row shows while an action is in flight and after it.
void main() {
  late FakeDeviceRepository repository;

  // Created inside the test body (the widget test's fake-async zone), like
  // device_list_popup_test.dart, so tester.pump() flushes stream events.
  Future<void> showPopup(WidgetTester tester, {bool mirroring = false}) async {
    repository = FakeDeviceRepository();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(value: cubit, child: const DeviceListPopup()),
    ));
    repository.connectedController.add(true);
    repository.devicesController.add([_phone(mirroring: mirroring)]);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<ButtonStyleButton>(find.ancestor(
          of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()))
      .enabled;

  testWidgets('the buttons are disabled while an action is in flight, so a '
      'second tap sends nothing', (tester) async {
    await showPopup(tester);
    repository.commandGate = Completer<void>();

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(enabled(tester, 'Play'), isFalse);
    expect(enabled(tester, 'Go Wireless'), isFalse);

    await tester.tap(find.text('Play'));
    await tester.tap(find.text('Go Wireless'));
    await tester.pump();
    expect(repository.playedSerials, [_serial]);
    expect(repository.wirelessSerials, isEmpty);

    repository.commandGate!.complete();
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Play'), isTrue);
    expect(enabled(tester, 'Go Wireless'), isTrue);
  });

  testWidgets('a failed Play is explained on the row', (tester) async {
    await showPopup(tester);
    repository.commandError = const DaemonCommandException(
        DaemonCommandFailure.rejected, 'ProcessException: file not found');

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not start mirroring: ProcessException: file not found'),
      findsOneWidget,
    );
    expect(find.text('Play'), findsOneWidget,
        reason: 'mirroring still follows the daemon, which did not change');
  });

  testWidgets('a failed Stop is explained on the row', (tester) async {
    await showPopup(tester, mirroring: true);
    repository.commandError =
        const DaemonCommandException(DaemonCommandFailure.disconnected);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Could not stop mirroring: not connected to the background service'),
      findsOneWidget,
    );
  });

  testWidgets('Play on a phone already mirroring says so', (tester) async {
    await showPopup(tester);
    repository.launchOutcome = LaunchOutcome.alreadyRunning;

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('Already mirroring.'), findsOneWidget);
  });

  group('a Go Wireless the daemon turns away shows its reason once', () {
    const reason = 'Go Wireless is already in progress for this phone';
    const event =
        StatusEvent(serial: _serial, stage: 'alreadyRunning', detail: reason);

    testWidgets('when the status event arrives before the reply',
        (tester) async {
      await showPopup(tester);
      repository.commandGate = Completer<void>();

      await tester.tap(find.text('Go Wireless'));
      await tester.pump();
      repository.wirelessStatusController.add(event);
      await tester.pump();
      repository.commandGate!.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining(reason), findsOneWidget);
    });

    testWidgets('when the reply arrives before the status event',
        (tester) async {
      await showPopup(tester);

      await tester.tap(find.text('Go Wireless'));
      await tester.pumpAndSettle();
      repository.wirelessStatusController.add(event);
      await tester.pumpAndSettle();

      expect(find.textContaining(reason), findsOneWidget);
    });
  });
}
