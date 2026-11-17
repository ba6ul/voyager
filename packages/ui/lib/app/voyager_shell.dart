import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/daemon/daemon_launcher.dart';
import '../core/theme/retro_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/pixel_border.dart';
import '../core/widgets/pixel_icon.dart';
import '../core/widgets/retro_widgets.dart';
import '../features/devices/presentation/cubit/device_list_cubit.dart';
import '../features/devices/presentation/cubit/device_list_state.dart';
import '../features/file_share/presentation/file_share_workspace.dart';
import '../features/flutter_dev/presentation/flutter_workspace.dart';
import '../features/home/presentation/home_workspace.dart';
import '../features/recording/presentation/recording_workspace.dart';
import 'app_section.dart';

/// The handheld: a header strip, a key rail down the left, the LCD with the
/// active workspace on it, and a status bar. F1-F4 switch workspaces.
class VoyagerShell extends StatefulWidget {
  const VoyagerShell({
    super.key,
    required this.theme,
    this.initial,
    this.daemonLauncher,
  });

  /// Lets Home start the daemon when it is not running.
  final DaemonLauncher? daemonLauncher;

  final ThemeController theme;
  final AppSection? initial;

  @override
  State<VoyagerShell> createState() => _VoyagerShellState();
}

class _VoyagerShellState extends State<VoyagerShell>
    with SingleTickerProviderStateMixin {
  late AppSection _section = widget.initial ?? AppSection.home;

  // A short flicker when the screen changes, like a cheap LCD refreshing.
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  void _select(AppSection section) {
    if (section == _section) return;
    setState(() => _section = section);
    _flicker.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return CallbackShortcuts(
      bindings: {
        for (final s in AppSection.values)
          SingleActivator(s.key): () => _select(s),
      },
      child: Focus(
        autofocus: true,
        // A Scaffold, not just a Material: snack bars ("coming soon") need one.
        child: Scaffold(
          backgroundColor: p.shell,
          body: Column(
            children: [
              _Header(section: _section, theme: widget.theme),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NavRail(selected: _section, onSelect: _select),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 12, 10),
                        child: _Screen(
                          scanlines: widget.theme.scanlines,
                          flicker: _flicker,
                          child: IndexedStack(
                            index: _section.index,
                            children: [
                              HomeWorkspace(
                                  daemonLauncher: widget.daemonLauncher),
                              const FlutterWorkspace(),
                              const FileShareWorkspace(),
                              const RecordingWorkspace(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const _StatusBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The LCD: a recessed, stepped-corner window with optional scanlines.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.child,
    required this.scanlines,
    required this.flicker,
  });

  final Widget child;
  final bool scanlines;
  final Animation<double> flicker;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final shape = PixelBorder(
      side: BorderSide(color: p.ink, width: 3),
      step: 3,
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.screen,
        shape: shape,
        shadows: [BoxShadow(color: p.shellDark, offset: const Offset(0, 3))],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: flicker,
              builder: (_, child) {
                final t = flicker.value;
                final opacity = t < 0.2
                    ? 0.25
                    : (t < 0.4 ? 1.0 : (t < 0.55 ? 0.6 : 1.0));
                return Opacity(opacity: opacity, child: child);
              },
              child: Padding(padding: const EdgeInsets.all(3), child: child),
            ),
            if (scanlines) const ScanlineOverlay(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.section, required this.theme});

  final AppSection section;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const PixelIcon(PixelGlyph.star, size: 24),
          const SizedBox(width: 10),
          Text('VOYAGER', style: context.pixel(size: 16)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              '/ ${section.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: 22, color: p.inkDim),
            ),
          ),
          const Spacer(),
          _HeaderButton(
            label: p.name,
            tooltip: 'Change the screen colours',
            onTap: theme.nextPalette,
          ),
          const SizedBox(width: 8),
          _HeaderButton(
            label: theme.scanlines ? 'CRT ON' : 'CRT OFF',
            tooltip: 'Scanlines on or off',
            onTap: theme.toggleScanlines,
          ),
          const SizedBox(width: 12),
          const _Clock(),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(border: Border.all(color: p.ink, width: 2)),
          child: Text(label, style: context.pixel()),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
      '${two(now.hour)}:${two(now.minute)}',
      style: context.body(size: 26),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelect});

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in AppSection.values) ...[
              PixelKey(
                glyph: s.glyph,
                label: s.label,
                hint: s.keyName,
                selected: s == selected,
                tooltip: s.title,
                onPressed: () => onSelect(s),
              ),
              const SizedBox(height: 10),
            ],
            const Spacer(),
            PixelKey(
              glyph: PixelGlyph.gear,
              label: 'SETUP',
              compact: true,
              tooltip: 'Settings',
              onPressed: () => showNotWired(context, 'Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Link state, unit count, the engine credit and the key legend.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return BlocBuilder<DeviceListCubit, DeviceListState>(
      builder: (context, state) {
        final (text, on) = switch (state.connection) {
          DaemonConnection.initial => ('LINKING', false),
          DaemonConnection.unreachable => ('NO LINK', false),
          DaemonConnection.connected => ('LINK OK', true),
        };
        final count = state.devices.length;
        return Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.shellDark.withValues(alpha: p.isDark ? 0.6 : 0.35),
          ),
          child: Row(
            children: [
              Led(on: on, size: 10),
              const SizedBox(width: 6),
              Text(text, style: context.pixel()),
              const SizedBox(width: 12),
              Text(
                '$count UNIT${count == 1 ? '' : 'S'}',
                style: context.pixel(color: p.inkDim),
              ),
              const Spacer(),
              // scrcpy is the mirroring engine underneath, not the name of
              // the app.
              Flexible(
                child: Text(
                  'Mirroring by scrcpy',
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 18, color: p.inkDim),
                ),
              ),
              const Spacer(),
              Text(
                'F1-F4 PAGE  ESC HIDE',
                style: context.pixel(color: p.inkDim),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Keys for [AppSection]; kept here so the enum stays free of Flutter input
/// types in its public surface.
extension AppSectionKeys on AppSection {
  LogicalKeyboardKey get key => switch (this) {
    AppSection.home => LogicalKeyboardKey.f1,
    AppSection.flutter => LogicalKeyboardKey.f2,
    AppSection.files => LogicalKeyboardKey.f3,
    AppSection.recording => LogicalKeyboardKey.f4,
  };

  String get keyName => 'F${index + 1}';
}
