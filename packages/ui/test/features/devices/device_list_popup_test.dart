import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/cached_device.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list_popup.dart';

import 'fake_device_repository.dart';

// Shaped like the real cache entry and live serial from a Pixel that had gone
// wireless before and was later connected through wireless debugging.
const _cached = CachedDevice(
  usbSerial: '65261XEA33U4D0',
  model: 'Pixel 10a',
  lastIp: '192.168.1.6',
  lastPort: 5555,
);
const _liveMdns = Device(
  serial: 'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp',
  state: DeviceState.device,
  model: 'Pixel 10a',
  mirroring: false,
);

void main() {
  late FakeDeviceRepository repository;
  late DeviceListCubit cubit;

  // The repository and cubit are created inside the test body, i.e. inside the
  // widget test's fake-async zone; made in setUp, their stream events would
  // not be flushed by tester.pump().
  Future<void> showPopup(WidgetTester tester) async {
    repository = FakeDeviceRepository();
    cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(value: cubit, child: const DeviceListPopup()),
    ));
    repository.connectedController.add(true);
    await tester.pump();
  }

  group('pending reconnect row', () {
    testWidgets('is shown for a remembered phone that is not connected',
        (tester) async {
      await showPopup(tester);

      repository.knownDevicesController.add([_cached]);
      await tester.pump();

      expect(find.text('Pixel 10a'), findsOneWidget);
      expect(find.textContaining('previously connected'), findsOneWidget);
      expect(find.text('Try Now'), findsOneWidget);
    });

    testWidgets('does not duplicate a phone that is already listed',
        (tester) async {
      await showPopup(tester);

      repository.knownDevicesController.add([_cached]);
      repository.devicesController.add([_liveMdns]);
      await tester.pump();

      // One row for the live device, none for the cache entry.
      expect(find.text('Pixel 10a'), findsOneWidget);
      expect(find.text('Try Now'), findsNothing);
      expect(find.textContaining('previously connected'), findsNothing);
    });

    testWidgets('shows progress while retrying, then why it did not work',
        (tester) async {
      await showPopup(tester);
      repository.knownDevicesController.add([_cached]);
      await tester.pump();
      repository.retryGate = Completer<void>();
      repository.retryResult = const RetryResult(
        RetryOutcome.unreachable,
        address: '192.168.1.6:5555',
      );

      await tester.tap(find.text('Try Now'));
      await tester.pump();

      expect(find.text('Trying…'), findsOneWidget);
      expect(find.text('Try Now'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.retryGate!.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Trying…'), findsNothing);
      expect(find.text('Try Now'), findsOneWidget);
      expect(find.textContaining('No answer from 192.168.1.6:5555'),
          findsOneWidget);
      expect(find.textContaining('plug it in with USB'), findsOneWidget);
    });

    testWidgets('a second tap while retrying does not send another request',
        (tester) async {
      await showPopup(tester);
      repository.knownDevicesController.add([_cached]);
      await tester.pump();
      repository.retryGate = Completer<void>();

      await tester.tap(find.text('Try Now'));
      await tester.pump();
      // The button is replaced by a disabled "Trying…" one; tapping is inert.
      await tester.tap(find.text('Trying…'), warnIfMissed: false);
      await tester.pump();

      expect(repository.retryReconnectSerials, ['65261XEA33U4D0']);
      repository.retryGate!.complete();
      await tester.pump();
    });
  });

  group('branding', () {
    testWidgets('the heading is Voyager and scrcpy is credited as the engine',
        (tester) async {
      await showPopup(tester);

      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Voyager')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('scrcpy')),
        findsNothing,
      );
      expect(find.text('Mirroring by scrcpy'), findsOneWidget);
    });

    testWidgets('the name is shown even while the daemon is not running',
        (tester) async {
      await showPopup(tester);
      repository.connectedController.add(false);
      await tester.pump();

      expect(find.text('Daemon not running'), findsOneWidget);
      expect(find.text('Voyager'), findsOneWidget);
    });
  });

  group('actions by transport', () {
    // One phone on USB (mirroring, so Handoff applies), and the three kinds
    // that must not be offered Go Wireless or Handoff.
    const usb = Device(
        serial: '65261XEA33U4D0',
        state: DeviceState.device,
        model: 'Pixel 10a',
        mirroring: true);
    const mdns = Device(
        serial: 'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp',
        state: DeviceState.device,
        model: 'Pixel 10a',
        mirroring: true);
    const emulator = Device(
        serial: 'emulator-5554',
        state: DeviceState.device,
        model: 'sdk_gphone64_x86_64',
        mirroring: true);
    const network = Device(
        serial: '192.168.43.1:5555',
        state: DeviceState.device,
        model: 'Pixel 10a',
        mirroring: true);

    testWidgets('a USB phone is offered Go Wireless and Handoff',
        (tester) async {
      await showPopup(tester);

      repository.devicesController.add([usb]);
      await tester.pump();

      expect(find.text('Go Wireless'), findsOneWidget);
      expect(find.text('Handoff'), findsOneWidget);
    });

    testWidgets('wireless debugging, an emulator and an ip:port address are '
        'not offered either, and say what they are', (tester) async {
      // Regression for #28: the wireless-debugging phone and the emulator both
      // got Go Wireless and Handoff because their serials have no colon.
      await showPopup(tester);

      repository.devicesController.add([mdns, emulator, network]);
      await tester.pump();

      expect(find.text('Go Wireless'), findsNothing);
      expect(find.text('Handoff'), findsNothing);
      // They can still be played and stopped.
      expect(find.text('Stop'), findsNWidgets(3));
      expect(find.textContaining('(wireless debugging)'), findsOneWidget);
      expect(find.textContaining('(emulator)'), findsOneWidget);
      expect(find.textContaining('(wireless)'), findsOneWidget);
    });

    testWidgets('only the USB row among mixed devices has the buttons',
        (tester) async {
      await showPopup(tester);

      repository.devicesController.add([mdns, usb, emulator]);
      await tester.pump();

      expect(find.text('Go Wireless'), findsOneWidget);
      expect(find.text('Handoff'), findsOneWidget);
    });
  });
}
