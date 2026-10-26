import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

import 'core/ipc/ipc_connection.dart';
import 'core/tray/tray_controller.dart';
import 'features/devices/data/daemon_device_repository.dart';
import 'features/devices/presentation/cubit/device_list_cubit.dart';
import 'features/devices/presentation/widgets/device_list_popup.dart';

const _windowOptions = WindowOptions(
  size: Size(360, 480),
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

  runApp(VoyagerApp(cubit: cubit));
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

class VoyagerApp extends StatelessWidget {
  const VoyagerApp({super.key, required this.cubit});

  final DeviceListCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        title: 'Voyager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const DeviceListPopup(),
      ),
    );
  }
}
