import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Wraps tray_manager: the tray icon + context menu, and what tapping them
/// does to the (otherwise hidden) main window.
class AppTrayController with TrayListener {
  Future<void> init({required String iconPath}) async {
    trayManager.addListener(this);
    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Voyager');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Show'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'quit':
        windowManager.destroy();
        break;
    }
  }

  void _showWindow() {
    windowManager.show();
    windowManager.focus();
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
