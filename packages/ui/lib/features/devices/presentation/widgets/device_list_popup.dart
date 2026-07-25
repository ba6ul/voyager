import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/device_list_cubit.dart';
import '../cubit/device_list_state.dart';
import 'device_row.dart';

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
              if (state.devices.isEmpty) {
                return const Center(child: Text('No devices connected'));
              }
              final cubit = context.read<DeviceListCubit>();
              return ListView.separated(
                itemCount: state.devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final device = state.devices[index];
                  return DeviceRow(
                    device: device,
                    statusMessage: state.statusMessages[device.serial],
                    onPlay: () => cubit.play(device.serial),
                    onStop: () => cubit.stop(device.serial),
                    onGoWireless: () => cubit.goWireless(device.serial),
                    onHandoff: () => cubit.handoff(device.serial),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
