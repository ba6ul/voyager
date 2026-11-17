import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/app/voyager_shell.dart';
import 'package:scrcpy_ui/core/theme/retro_palette.dart';
import 'package:scrcpy_ui/core/theme/retro_theme.dart';
import 'package:scrcpy_ui/core/theme/theme_controller.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/main.dart' show minWindowSize;

import '../features/devices/fake_device_repository.dart';

void main() {
  late FakeDeviceRepository repository;
  late ThemeController theme;

  Future<void> showShell(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? minWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = FakeDeviceRepository();
    theme = ThemeController();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: buildRetroTheme(RetroPalette.lcd),
          home: VoyagerShell(theme: theme),
        ),
      ),
    );
    repository.connectedController.add(true);
    repository.devicesController.add(const [
      Device(
        serial: '65261XEA33U4D0',
        state: DeviceState.device,
        model: 'Pixel 10a',
        mirroring: true,
      ),
    ]);
    await tester.pump();
  }

  testWidgets('shows the name, the engine credit and Home with its actions', (
    tester,
  ) async {
    await showShell(tester);

    expect(find.text('VOYAGER'), findsOneWidget);
    expect(find.text('Mirroring by scrcpy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The real device list is on Home with its real actions.
    expect(find.text('Pixel 10a'), findsWidgets);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Go Wireless'), findsOneWidget);
    expect(find.text('Handoff'), findsOneWidget);
  });

  testWidgets('the name is shown even while the daemon is not running', (
    tester,
  ) async {
    await showShell(tester);
    repository.connectedController.add(false);
    await tester.pump();

    expect(find.text('VOYAGER'), findsOneWidget);
    expect(find.text('NO LINK'), findsOneWidget);
  });

  for (final size in [minWindowSize, const Size(980, 640)]) {
    testWidgets('every workspace lays out at $size without overflow', (
      tester,
    ) async {
      await showShell(tester, size: size);
      for (final key in [
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f1,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: '$key');
      }
    });
  }

  testWidgets('F2 to F4 switch workspace, F1 returns Home', (tester) async {
    await showShell(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(find.text('/ FLUTTER / APP DEVELOPMENT'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(find.text('/ FILE SHARING / TRANSFER'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pump();
    expect(find.text('/ RECORDING / MONITOR'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    expect(find.text('/ HOME / DEVICE CONTROL'), findsOneWidget);
  });

  testWidgets('a nav key click switches workspace', (tester) async {
    await showShell(tester);

    await tester.tap(find.text('FILES'));
    await tester.pump();

    expect(find.text('/ FILE SHARING / TRANSFER'), findsOneWidget);
  });

  testWidgets('an unwired control says so instead of doing nothing', (
    tester,
  ) async {
    await showShell(tester);

    await tester.tap(find.text('SHOT'));
    await tester.pump();

    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  testWidgets('the console answers: devices is real, others are not wired', (
    tester,
  ) async {
    await showShell(tester);

    await tester.enterText(find.byType(TextField), 'devices');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(); // the console scrolls to the new line after a frame
    expect(find.textContaining('65261XEA33U4D0\tdevice'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'shell ls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("'shell' is not wired yet"), findsOneWidget);
  });

  testWidgets('the palette button cycles the palette', (tester) async {
    await showShell(tester);
    expect(theme.palette.name, 'LCD');

    await tester.tap(find.text('LCD'));
    await tester.pump();

    expect(theme.palette.name, 'CRT GREEN');
  });

  testWidgets('the simulated Flutter run starts and stops cleanly', (
    tester,
  ) async {
    await showShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();

    await tester.tap(find.text('RUN'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('[SIM]'), findsWidgets);

    await tester.tap(find.text('STOP'));
    await tester.pump();
    expect(find.text('[SIM] Application finished.'), findsOneWidget);
  });
}
