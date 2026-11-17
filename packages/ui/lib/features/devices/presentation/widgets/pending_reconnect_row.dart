import 'package:flutter/material.dart';

import '../../../../core/theme/retro_theme.dart';
import '../../../../core/widgets/pixel_border.dart';
import '../../../../core/widgets/pixel_icon.dart';
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
    final p = context.retro;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 3),
      child: DecoratedBox(
        // Dim outline: the phone is remembered, not present.
        decoration: ShapeDecoration(
          color: p.panel,
          shape: PixelBorder(side: BorderSide(color: p.inkDim, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PixelIcon(PixelGlyph.wifi, size: 24, color: p.inkDim),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.model,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Trying…'),
                    ],
                  ),
                )
              else
                OutlinedButton(
                  onPressed: onTryNow,
                  child: const Text('Try Now'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
