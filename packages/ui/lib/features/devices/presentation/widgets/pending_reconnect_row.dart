import 'package:flutter/material.dart';

import '../../domain/entities/cached_device.dart';

/// A device that has gone wireless before but isn't currently reachable.
/// The daemon retries it in the background on its own every few seconds;
/// this row just lets the user nudge that retry immediately.
class PendingReconnectRow extends StatelessWidget {
  const PendingReconnectRow({
    super.key,
    required this.device,
    required this.onTryNow,
  });

  final CachedDevice device;
  final VoidCallback onTryNow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.model, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'previously connected – reconnecting…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          OutlinedButton(onPressed: onTryNow, child: const Text('Try Now')),
        ],
      ),
    );
  }
}
