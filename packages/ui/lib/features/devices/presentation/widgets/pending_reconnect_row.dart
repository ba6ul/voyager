import 'package:flutter/material.dart';

import '../../domain/entities/cached_device.dart';
import '../cubit/device_list_state.dart';

/// A device that has gone wireless before but isn't currently reachable.
/// The daemon retries it in the background on its own every few seconds;
/// this row just lets the user nudge that retry immediately.
class PendingReconnectRow extends StatelessWidget {
  const PendingReconnectRow({
    super.key,
    required this.device,
    required this.onTryNow,
    this.status,
  });

  final CachedDevice device;
  final VoidCallback onTryNow;

  /// Progress or outcome of the last "Try Now", if any.
  final RetryStatus? status;

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
                  status?.message ?? 'previously connected – reconnecting…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (status?.inProgress ?? false)
            const OutlinedButton(
              onPressed: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Trying…'),
                ],
              ),
            )
          else
            OutlinedButton(onPressed: onTryNow, child: const Text('Try Now')),
        ],
      ),
    );
  }
}
