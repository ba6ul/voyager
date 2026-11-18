import 'package:flutter/material.dart';

import '../../../../core/theme/retro_theme.dart';
import '../../../../core/widgets/pixel_border.dart';
import '../../../../core/widgets/pixel_icon.dart';
import '../../../../core/widgets/retro_widgets.dart';
import '../../domain/entities/device.dart';
import '../cubit/device_list_state.dart';
import '../device_state_text.dart';

/// One phone as a card: LED, name, address and the actions that apply.
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
    final p = context.retro;
    final title = device.model ?? device.serial;
    final label = device.transportLabel;
    final subtitle = label == null
        ? device.serial
        : '${device.serial} ($label)';
    final canHandoff =
        device.isReady && device.canGoWireless && device.mirroring;
    // One command at a time per device; a disabled button sends nothing.
    final busy = action?.inProgress ?? false;
    VoidCallback? unlessBusy(VoidCallback callback) => busy ? null : callback;
    final actionMessage = action?.message;
    final stateText = describeDeviceState(device.state);
    final small = Theme.of(context).textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 3),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.screen,
          shape: PixelBorder(side: BorderSide(color: p.ink, width: 2)),
          shadows: [BoxShadow(color: p.shadow, offset: const Offset(3, 3))],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: PixelIcon(switch (device.transport) {
                      DeviceTransport.usb => PixelGlyph.usb,
                      DeviceTransport.emulator => PixelGlyph.terminal,
                      _ => PixelGlyph.wifi,
                    }, size: 24),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(subtitle, style: small),
                      ],
                    ),
                  ),
                  // Flexible, so a long label wraps instead of overflowing
                  // the row at the minimum window width or with a large
                  // system text size.
                  if (!device.isReady)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          stateText.label,
                          textAlign: TextAlign.end,
                          style: context.body(color: p.warn),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Led(on: true, color: device.mirroring ? p.ink : p.ok),
                          if (device.mirroring) ...[
                            const SizedBox(width: 6),
                            Text('LIVE', style: context.pixel(size: 8)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              if (!device.isReady && stateText.hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(stateText.hint!, style: small),
                ),
              if (actionMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(actionMessage, style: small),
                ),
              if (statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(statusMessage!, style: small),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (device.isReady)
                    device.mirroring
                        ? OutlinedButton(
                            onPressed: unlessBusy(onStop),
                            child: const Text('Stop'),
                          )
                        : FilledButton(
                            onPressed: unlessBusy(onPlay),
                            child: const Text('Play'),
                          ),
                  if (device.isReady && device.canGoWireless)
                    OutlinedButton(
                      onPressed: unlessBusy(onGoWireless),
                      child: const Text('Go Wireless'),
                    ),
                  if (canHandoff)
                    OutlinedButton(
                      onPressed: unlessBusy(onHandoff),
                      child: const Text('Handoff'),
                    ),
                  // Only for an address added with `adb connect`; wireless
                  // debugging and emulators are not the app's to disconnect.
                  // Offered in any state, so a stuck "offline" entry can be
                  // dropped.
                  if (device.transport == DeviceTransport.network)
                    OutlinedButton(
                      onPressed: unlessBusy(onDisconnect),
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
