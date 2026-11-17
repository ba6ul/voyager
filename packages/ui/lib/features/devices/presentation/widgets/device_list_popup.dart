import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/device_list_cubit.dart';
import '../cubit/device_list_state.dart';
import '../device_state_text.dart';
import 'device_row.dart';
import 'pending_reconnect_row.dart';

class DeviceListPopup extends StatelessWidget {
  const DeviceListPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voyager')),
      // scrcpy is the mirroring engine underneath, not the name of the app.
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Mirroring by scrcpy',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      body: BlocBuilder<DeviceListCubit, DeviceListState>(
        builder: (context, state) {
          switch (state.connection) {
            case DaemonConnection.initial:
              return const _Message(
                title: connectingText,
                showSpinner: true,
              );
            case DaemonConnection.unreachable:
              return const _Message(
                title: unreachableTitle,
                hint: unreachableHint,
              );
            case DaemonConnection.connected:
              final pending = state.pendingReconnect;
              if (state.devices.isEmpty && pending.isEmpty) {
                return const _Message(
                  title: noDevicesTitle,
                  hint: noDevicesHint,
                );
              }
              final cubit = context.read<DeviceListCubit>();
              return ListView(
                children: [
                  for (final cached in pending)
                    PendingReconnectRow(
                      device: cached,
                      status: state.retries[cached.usbSerial],
                      onTryNow: () => cubit.retryReconnect(cached.usbSerial),
                    ),
                  if (pending.isNotEmpty && state.devices.isNotEmpty)
                    const Divider(height: 1),
                  for (var i = 0; i < state.devices.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    DeviceRow(
                      device: state.devices[i],
                      statusMessage: state.statusMessages[state.devices[i].serial],
                      action: state.actions[state.devices[i].serial],
                      onPlay: () => cubit.play(state.devices[i].serial),
                      onStop: () => cubit.stop(state.devices[i].serial),
                      onGoWireless: () => cubit.goWireless(state.devices[i].serial),
                      onHandoff: () => cubit.handoff(state.devices[i].serial),
                    ),
                  ],
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
  const _Message({required this.title, this.hint, this.showSpinner = false});

  final String title;
  final String? hint;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
            ],
            Text(title, textAlign: TextAlign.center, style: theme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint!, textAlign: TextAlign.center, style: theme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
