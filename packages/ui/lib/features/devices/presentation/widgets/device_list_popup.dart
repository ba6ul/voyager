import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/device_list_cubit.dart';
import '../cubit/device_list_state.dart';
import 'device_row.dart';
import 'pending_reconnect_row.dart';

class DeviceListPopup extends StatelessWidget {
  const DeviceListPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('scrcpy')),
      body: BlocBuilder<DeviceListCubit, DeviceListState>(
        builder: (context, state) {
          switch (state.connection) {
            case DaemonConnection.initial:
              return const Center(child: CircularProgressIndicator());
            case DaemonConnection.unreachable:
              return const Center(child: Text('Daemon not running'));
            case DaemonConnection.connected:
              final pending = state.pendingReconnect;
              if (state.devices.isEmpty && pending.isEmpty) {
                return const Center(child: Text('No devices connected'));
              }
              final cubit = context.read<DeviceListCubit>();
              return ListView(
                children: [
                  for (final cached in pending)
                    PendingReconnectRow(
                      device: cached,
                      onTryNow: () => cubit.retryReconnect(cached.usbSerial),
                    ),
                  if (pending.isNotEmpty && state.devices.isNotEmpty)
                    const Divider(height: 1),
                  for (var i = 0; i < state.devices.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    DeviceRow(
                      device: state.devices[i],
                      statusMessage: state.statusMessages[state.devices[i].serial],
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
