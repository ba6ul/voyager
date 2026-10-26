import 'package:flutter/material.dart';

import '../../domain/entities/device.dart';

class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.statusMessage,
    required this.onPlay,
    required this.onStop,
    required this.onGoWireless,
    required this.onHandoff,
  });

  final Device device;
  final String? statusMessage;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onGoWireless;
  final VoidCallback onHandoff;

  @override
  Widget build(BuildContext context) {
    final title = device.model ?? device.serial;
    final subtitle =
        device.isNetwork ? '${device.serial} (wireless)' : device.serial;
    final canHandoff = device.isReady && !device.isNetwork && device.mirroring;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (!device.isReady)
                Text(
                  device.state.name,
                  style: const TextStyle(color: Colors.orange),
                ),
            ],
          ),
          if (statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                statusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (device.isReady)
                device.mirroring
                    ? OutlinedButton(onPressed: onStop, child: const Text('Stop'))
                    : FilledButton(onPressed: onPlay, child: const Text('Play')),
              if (device.isReady && !device.isNetwork)
                OutlinedButton(
                  onPressed: onGoWireless,
                  child: const Text('Go Wireless'),
                ),
              if (canHandoff)
                OutlinedButton(onPressed: onHandoff, child: const Text('Handoff')),
            ],
          ),
        ],
      ),
    );
  }
}
