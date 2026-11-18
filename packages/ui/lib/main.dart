import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import 'app/voyager_shell.dart';
import 'core/daemon/daemon_launcher.dart';
import 'core/ipc/ipc_connection.dart';
import 'core/theme/retro_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/tray/tray_controller.dart';
import 'features/devices/data/daemon_device_repository.dart';
import 'features/devices/presentation/cubit/device_list_cubit.dart';
import 'features/devices/presentation/cubit/device_list_state.dart';
import 'features/devices/presentation/tray_tooltip.dart';
import 'features/devices/presentation/widgets/hide_on_escape.dart';

/// The smallest window the shell is laid out for; voyager_shell_test.dart
/// renders every workspace at exactly this size.
const minWindowSize = Size(760, 520);

const _windowOptions = WindowOptions(
  size: Size(980, 640),
  minimumSize: minWindowSize,
  center: true,
  skipTaskbar: true,
  title: 'Voyager',
  titleBarStyle: TitleBarStyle.normal,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // No default visible window: start hidden, only shown via the tray icon
  // or when a device becomes ready.
  await windowManager.waitUntilReadyToShow(_windowOptions, () async {
    await windowManager.hide();
  });
  await windowManager.setPreventClose(true);
  windowManager.addListener(_HideInsteadOfCloseListener());

  final tray = AppTrayController();
  await tray.init(iconPath: 'assets/tray_icon.ico');

  final repository = DaemonDeviceRepository(IpcConnection());
  final cubit = DeviceListCubit(
    repository,
    onDeviceReady: (_) {
      windowManager.show();
      windowManager.focus();
    },
  );

  // Keep the tray tooltip in step with the device list; set only on change.
  var tooltip = '';
  void updateTooltip(DeviceListState state) {
    final next = describeTray(state);
    if (next == tooltip) return;
    tooltip = next;
    tray.setToolTip(next);
  }

  updateTooltip(cubit.state);
  cubit.stream.listen(updateTooltip);

  runApp(VoyagerApp(cubit: cubit, onHide: windowManager.hide));
}

/// Clicking the window's close button hides it (the app keeps running in
/// the tray) instead of quitting; use the tray menu's Quit to actually exit.
class _HideInsteadOfCloseListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}

class VoyagerApp extends StatefulWidget {
  const VoyagerApp({
    super.key,
    required this.cubit,
    required this.onHide,
    this.theme,
  });

  final DeviceListCubit cubit;

  /// Puts the window away (Esc); the app keeps running in the tray.
  final VoidCallback onHide;

  /// Palette and scanline switches; a fresh one if not given.
  final ThemeController? theme;

  @override
  State<VoyagerApp> createState() => _VoyagerAppState();
}

class _VoyagerAppState extends State<VoyagerApp> {
  late final ThemeController _theme = widget.theme ?? ThemeController();

  @override
  void dispose() {
    if (widget.theme == null) _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: ListenableBuilder(
        listenable: _theme,
        builder: (context, _) => MaterialApp(
          title: 'Voyager',
          debugShowCheckedModeBanner: false,
          theme: buildRetroTheme(_theme.palette),
          home: HideOnEscape(
            onHide: widget.onHide,
            child: VoyagerShell(
              theme: _theme,
              daemonLauncher: const LocalDaemonLauncher(),
            ),
          ),
        ),
      ),
    );
  }
}
