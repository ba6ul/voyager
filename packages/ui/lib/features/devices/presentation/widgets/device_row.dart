import 'package:flutter/material.dart';

import '../../domain/entities/device.dart';
import '../cubit/device_list_state.dart';

class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.statusMessage,
    required this.onPlay,
    required this.onStop,
    required this.onGoWireless,
    required this.onHandoff,
    required this.onDisconnect,
    this.action,
  });

  final Device device;
  final String? statusMessage;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onGoWireless;
  final VoidCallback onHandoff;
  final VoidCallback onDisconnect;

  /// The last action sent for this device: while it is in flight the buttons
  /// are disabled; once finished, its message (if any) is shown.
  final DeviceActionStatus? action;

  @override
  Widget build(BuildContext context) {
    final title = device.model ?? device.serial;
    final label = device.transportLabel;
    final subtitle = label == null ? device.serial : '${device.serial} ($label)';
    final canHandoff = device.isReady && device.canGoWireless && device.mirroring;
    // One command at a time per device; a disabled button sends nothing.
    final busy = action?.inProgress ?? false;
    VoidCallback? unlessBusy(VoidCallback callback) => busy ? null : callback;
    final actionMessage = action?.message;

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
          if (actionMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                actionMessage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                    ? OutlinedButton(
                        onPressed: unlessBusy(onStop), child: const Text('Stop'))
                    : FilledButton(
                        onPressed: unlessBusy(onPlay), child: const Text('Play')),
              if (device.isReady && device.canGoWireless)
                OutlinedButton(
                  onPressed: unlessBusy(onGoWireless),
                  child: const Text('Go Wireless'),
                ),
              if (canHandoff)
                OutlinedButton(
                    onPressed: unlessBusy(onHandoff),
                    child: const Text('Handoff')),
              // Only for an address added with `adb connect`; wireless
              // debugging and emulators are not the app's to disconnect.
              // Offered in any state, so a stuck "offline" entry can be dropped.
              if (device.transport == DeviceTransport.network)
                OutlinedButton(
                    onPressed: unlessBusy(onDisconnect),
                    child: const Text('Disconnect')),
            ],
          ),
        ],
      ),
    );
  }
}
