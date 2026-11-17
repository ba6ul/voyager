import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list_popup.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_row.dart';

import 'fake_device_repository.dart';

// The app's theme, as in main.dart.
final _theme = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo);

double _contrast(Color a, Color b) {
  final hi = a.computeLuminance() > b.computeLuminance() ? a : b;
  final lo = identical(hi, a) ? b : a;
  return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
}

void main() {
  test('the not-ready text has at least 4.5:1 contrast on the surface', () {
    final surface = _theme.colorScheme.surface;

    expect(_contrast(notReadyColor, surface), greaterThanOrEqualTo(4.5));
    // The colour it replaced did not, so this test can fail.
    expect(_contrast(Colors.orange, surface), lessThan(4.5));
  });

  // main.dart sets the window's minimum size to this.
  const minWindow = Size(320, 300);

  testWidgets('the busiest rows fit at the minimum window size',
      (tester) async {
    tester.view.physicalSize = minWindow;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = FakeDeviceRepository();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      theme: _theme,
      home: BlocProvider.value(value: cubit, child: const DeviceListPopup()),
    ));
    repository.connectedController.add(true);
    // Three buttons, a long model name.
    repository.devicesController.add(const [
      Device(
          serial: '65261XEA33U4D0',
          state: DeviceState.device,
          model: 'Galaxy S24 Ultra 5G Enterprise Edition',
          mirroring: true),
    ]);
    await tester.pump();
    // A RenderFlex overflow is reported as an exception.
    expect(tester.takeException(), isNull);
    expect(find.text('Handoff'), findsOneWidget);

    // A long serial with a status label beside it. (Shown alone: the list is
    // lazy, and a second row would be below the fold at this height.)
    repository.devicesController.add(const [
      Device(
          serial: 'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp',
          state: DeviceState.unauthorized,
          model: 'Pixel 10a',
          mirroring: false),
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Waiting for permission'), findsOneWidget);

    // Disconnect next to Stop.
    repository.devicesController.add(const [
      Device(
          serial: '192.168.43.1:5555',
          state: DeviceState.device,
          model: 'Pixel 10a',
          mirroring: true),
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Disconnect'), findsOneWidget);
  });
}
