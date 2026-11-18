import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/daemon/daemon_launcher.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import '../../devices/presentation/cubit/device_list_state.dart';
import '../../devices/presentation/widgets/device_list.dart';
import 'adb_console_panel.dart';
import 'unit_status_panel.dart';

/// Home / Device Control: the command centre. Units on the left (the real
/// device list and its actions), then the selected unit's read-out, quick
/// operations and an ADB console on the right.
class HomeWorkspace extends StatelessWidget {
  const HomeWorkspace({super.key, this.daemonLauncher});

  /// Lets the unreachable state start the daemon; omitted in tests.
  final DaemonLauncher? daemonLauncher;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: PixelPanel(
              title: 'UNITS',
              padding: EdgeInsets.zero,
              trailing: BlocBuilder<DeviceListCubit, DeviceListState>(
                buildWhen: (a, b) => a.devices.length != b.devices.length,
                builder: (context, state) =>
                    PixelBadge('${state.devices.length}', inverse: true),
              ),
              child: DeviceList(daemonLauncher: daemonLauncher),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const UnitStatusPanel(),
                const SizedBox(height: 12),
                const _QuickOps(),
                const SizedBox(height: 12),
                Expanded(
                    child: AdbConsolePanel(daemonLauncher: daemonLauncher)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickOps extends StatelessWidget {
  const _QuickOps();

  static const _ops = [
    (PixelGlyph.camera, 'SHOT', 'Screenshot'),
    (PixelGlyph.down, 'APK', 'Install an APK'),
    (PixelGlyph.up, 'PUSH', 'Push a file'),
    (PixelGlyph.power, 'BOOT', 'Reboot the phone'),
    (PixelGlyph.wifi, 'WIFI', 'Wi-Fi settings'),
    (PixelGlyph.terminal, 'LOGS', 'Open logcat'),
  ];

  @override
  Widget build(BuildContext context) {
    // A bare row of keys: every one answers with a "coming soon" notice.
    return Row(
      children: [
        for (var i = 0; i < _ops.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: PixelKey(
              glyph: _ops[i].$1,
              label: _ops[i].$2,
              tooltip: _ops[i].$3,
              compact: true,
              onPressed: () => showNotWired(context, _ops[i].$3),
            ),
          ),
        ],
      ],
    );
  }
}
