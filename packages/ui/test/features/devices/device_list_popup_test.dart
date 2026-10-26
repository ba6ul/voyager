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
}
