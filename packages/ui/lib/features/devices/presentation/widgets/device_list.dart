import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/daemon/daemon_launcher.dart';
import '../../../../core/theme/retro_theme.dart';
import '../../../../core/widgets/pixel_icon.dart';
import '../../../../core/widgets/retro_widgets.dart';
import '../cubit/device_list_cubit.dart';
import '../cubit/device_list_state.dart';
import '../device_state_text.dart';
import 'device_row.dart';
import 'pending_reconnect_row.dart';

/// The phones the daemon knows about, with their actions: the body of the
/// Home workspace's device panel. Shows the connecting, unreachable and
/// empty states in place of the rows.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key, this.daemonLauncher});

  /// When given, the unreachable state offers a button to start the daemon.
  final DaemonLauncher? daemonLauncher;

  @override
  Widget build(BuildContext context) {
    // Buttons and ink need a Material ancestor; the shell has one, this makes
    // the list safe to place anywhere.
    return Material(
      type: MaterialType.transparency,
      child: BlocBuilder<DeviceListCubit, DeviceListState>(
        builder: (context, state) {
          switch (state.connection) {
            case DaemonConnection.initial:
              return const _Message(title: connectingText, showSpinner: true);
            case DaemonConnection.unreachable:
              return _Message(
                glyph: PixelGlyph.warn,
                title: unreachableTitle,
                hint: unreachableHint,
                action: daemonLauncher == null
                    ? null
                    : _StartDaemonButton(launcher: daemonLauncher!),
              );
            case DaemonConnection.connected:
              final pending = state.pendingReconnect;
              if (state.devices.isEmpty && pending.isEmpty) {
                return const _Message(
                  glyph: PixelGlyph.usb,
                  title: noDevicesTitle,
                  hint: noDevicesHint,
                  noSignal: true,
                );
              }
              final cubit = context.read<DeviceListCubit>();
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final cached in pending)
                    PendingReconnectRow(
                      device: cached,
                      status: state.retries[cached.usbSerial],
                      onTryNow: () => cubit.retryReconnect(cached.usbSerial),
                    ),
                  for (var i = 0; i < state.devices.length; i++)
                    DeviceRow(
                      device: state.devices[i],
                      statusMessage:
                          state.statusMessages[state.devices[i].serial]?.text,
                      action: state.actions[state.devices[i].serial],
                      onPlay: () => cubit.play(state.devices[i].serial),
                      onStop: () => cubit.stop(state.devices[i].serial),
                      onGoWireless: () =>
                          cubit.goWireless(state.devices[i].serial),
                      onHandoff: () => cubit.handoff(state.devices[i].serial),
                      onDisconnect: () =>
                          cubit.disconnect(state.devices[i].serial),
                    ),
                ],
              );
          }
        },
      ),
    );
  }
}

/// A centred title with an optional hint line, for the states with no rows.
class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.hint,
    this.showSpinner = false,
    this.glyph,
    this.noSignal = false,
    this.action,
  });

  /// A button under the hint.
  final Widget? action;

  final String title;
  final String? hint;
  final bool showSpinner;
  final PixelGlyph? glyph;

  /// Draws the "no signal" test-pattern behind the text.
  final bool noSignal;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final theme = Theme.of(context).textTheme;
    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(),
              ),
              const SizedBox(height: 16),
            ] else if (glyph != null) ...[
              PixelIcon(glyph!, size: 40),
              const SizedBox(height: 14),
            ],
            Container(
              color: p.screen,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.titleMedium,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Container(
                color: p.screen,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: theme.bodyMedium?.copyWith(color: p.inkDim),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
    if (!noSignal) return content;
    return Stack(
      children: [
        const Positioned.fill(child: DitherFill(cell: 3, opacity: 0.12)),
        content,
      ],
    );
  }
}

/// Starts the daemon and says what happened. Once it is up the connection
/// retry finds it and this state is replaced by the device list.
class _StartDaemonButton extends StatefulWidget {
  const _StartDaemonButton({required this.launcher});

  final DaemonLauncher launcher;

  @override
  State<_StartDaemonButton> createState() => _StartDaemonButtonState();
}

class _StartDaemonButtonState extends State<_StartDaemonButton> {
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final error = await widget.launcher.start();
    if (!mounted) return;
    setState(() {
      _error = error;
      // On success stay "starting" until the connection appears (this widget
      // is then replaced); give up waiting after a while.
      _starting = error == null;
    });
    if (error == null) {
      await Future<void>.delayed(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'The service did not answer. Check the terminal it was '
              'started from, or try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: _starting ? null : _start,
          child: Text(_starting ? 'Starting...' : 'Start service'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            color: p.screen,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: context.body(color: p.warn)),
          ),
        ],
      ],
    );
  }
}
