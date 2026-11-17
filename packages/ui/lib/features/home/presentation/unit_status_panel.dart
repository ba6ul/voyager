import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_border.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/domain/entities/device.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import '../../devices/presentation/cubit/device_list_state.dart';
import '../../devices/presentation/device_state_text.dart';

/// Read-out for one phone. Link, state and mirroring come from the daemon;
/// battery and disk are made up (marked DEMO) until the daemon can report
/// them.
class UnitStatusPanel extends StatefulWidget {
  const UnitStatusPanel({super.key});

  @override
  State<UnitStatusPanel> createState() => _UnitStatusPanelState();
}

class _UnitStatusPanelState extends State<UnitStatusPanel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceListCubit, DeviceListState>(
      buildWhen: (a, b) => a.devices != b.devices,
      builder: (context, state) {
        final devices = state.devices;
        final index = devices.isEmpty ? 0 : _index.clamp(0, devices.length - 1);
        final device = devices.isEmpty ? null : devices[index];
        return PixelPanel(
          title: 'UNIT STATUS',
          // BATT and DISK are made up; say so on the title bar.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DemoBadge(label: 'BATT/DISK DEMO', onTitleBar: true),
              if (devices.length > 1) ...[
                const SizedBox(width: 8),
                _Pager(
                  index: index,
                  count: devices.length,
                  onChanged: (i) => setState(() => _index = i),
                ),
              ],
            ],
          ),
          child: device == null ? const _NoUnit() : _Readout(device: device),
        );
      },
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.index,
    required this.count,
    required this.onChanged,
  });

  final int index;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    Widget arrow(String t, int to) => InkWell(
      onTap: () => onChanged((to + count) % count),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: context.pixel(color: p.screen)),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow('<', index - 1),
        Text('${index + 1}/$count', style: context.pixel(color: p.screen)),
        arrow('>', index + 1),
      ],
    );
  }
}

class _NoUnit extends StatelessWidget {
  const _NoUnit();

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 72,
          child: Stack(
            children: [
              const Positioned.fill(child: DitherFill(cell: 3, opacity: 0.3)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: PixelBorder(
                      side: BorderSide(color: p.inkDim, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('NO SIGNAL', style: context.pixel(size: 8)),
                  const SizedBox(width: 6),
                  const Blink(child: Text('_')),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Connect a phone to see its read-out here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final state = describeDeviceState(device.state);
    final link = device.transportLabel ?? 'usb';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The phone's "screen": a tiny LCD with a big glyph; dithered while
        // it is mirroring.
        Container(
          width: 56,
          height: 72,
          decoration: ShapeDecoration(
            color: p.screen,
            shape: PixelBorder(side: BorderSide(color: p.ink, width: 2)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (device.mirroring)
                const Positioned.fill(
                  child: DitherFill(cell: 3, opacity: 0.25),
                ),
              PixelIcon(
                device.isReady ? PixelGlyph.phone : PixelGlyph.warn,
                size: 32,
                color: device.isReady ? p.ink : p.warn,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReadoutRow('MODEL', device.model ?? '?'),
              ReadoutRow(
                'LINK',
                '${link.toUpperCase()} / '
                    '${device.isReady ? 'READY' : state.label.toUpperCase()}',
                valueColor: device.isReady ? null : p.warn,
              ),
              ReadoutRow('MIRROR', device.mirroring ? 'ON AIR' : 'IDLE'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('BATT', style: context.pixel(color: p.inkDim)),
                  const SizedBox(width: 6),
                  const Expanded(child: SegmentBar(value: 0.78, height: 14)),
                  const SizedBox(width: 6),
                  Text('78%', style: context.body()),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('DISK', style: context.pixel(color: p.inkDim)),
                  const SizedBox(width: 6),
                  const Expanded(child: SegmentBar(value: 0.42, height: 14)),
                  const SizedBox(width: 6),
                  Text('42%', style: context.body()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
