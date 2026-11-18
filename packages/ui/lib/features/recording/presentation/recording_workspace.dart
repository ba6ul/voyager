import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import '../../devices/presentation/cubit/device_list_state.dart';

/// Recording / Monitor: a monitoring station. A CRT with a test pattern,
/// level meters, record controls and a clip shelf. Channels come from the
/// real device list; recording itself is a SIMULATION (a counting timecode
/// and wobbling meters) until screen capture is wired up.
class RecordingWorkspace extends StatefulWidget {
  const RecordingWorkspace({super.key});

  @override
  State<RecordingWorkspace> createState() => _RecordingWorkspaceState();
}

class _Clip {
  const _Clip(this.name, this.length, this.size);
  final String name;
  final String length;
  final String size;
}

class _RecordingWorkspaceState extends State<RecordingWorkspace> {
  final _clips = <_Clip>[
    const _Clip('clip_0003.mp4', '00:42', '18.2 MB'),
    const _Clip('clip_0002.mp4', '01:15', '31.7 MB'),
    const _Clip('clip_0001.mp4', '00:09', '3.9 MB'),
  ];
  final _random = Random(7);
  Timer? _timer;
  bool _recording = false;
  bool _paused = false;
  int _ticks = 0; // 100 ms each
  double _left = 0;
  double _right = 0;
  int _channel = 0;
  String _res = '1080P';
  String _fps = '60';
  bool _audio = true;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _record() {
    if (_recording) return;
    setState(() {
      _recording = true;
      _paused = false;
      _ticks = 0;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_paused) return;
      setState(() {
        _ticks++;
        _left = _audio ? 0.3 + _random.nextDouble() * 0.6 : 0;
        _right = _audio ? 0.25 + _random.nextDouble() * 0.65 : 0;
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    if (!_recording) return;
    setState(() {
      _clips.insert(
        0,
        _Clip(
          'clip_${(_clips.length + 1).toString().padLeft(4, '0')}.mp4',
          _timecode(short: true),
          '${(_ticks / 10 * 0.4).toStringAsFixed(1)} MB',
        ),
      );
      _recording = false;
      _paused = false;
      _left = _right = 0;
    });
  }

  String _timecode({bool short = false}) {
    final s = _ticks ~/ 10;
    String two(int n) => n.toString().padLeft(2, '0');
    final mm = two((s ~/ 60) % 60);
    final ss = two(s % 60);
    return short ? '$mm:$ss' : '${two(s ~/ 3600)}:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return BlocBuilder<DeviceListCubit, DeviceListState>(
      buildWhen: (a, b) => a.devices != b.devices,
      builder: (context, state) {
        final devices = state.devices;
        final channel = devices.isEmpty
            ? 0
            : _channel.clamp(0, devices.length - 1);
        final source = devices.isEmpty
            ? 'NO SOURCE'
            : (devices[channel].model ?? devices[channel].serial);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PixelPanel(
                        title: 'MONITOR',
                        trailing: _recording
                            ? Blink(
                                child: Text(
                                  _paused ? 'PAUSE' : 'REC',
                                  style: context.pixel(color: p.screen),
                                ),
                              )
                            : Text(
                                'STANDBY',
                                style: context.pixel(color: p.screen),
                              ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (devices.isEmpty)
                                  const PixelChip(
                                    'CH-- NONE',
                                    selected: false,
                                    onTap: null,
                                  ),
                                for (var i = 0; i < devices.length; i++)
                                  PixelChip(
                                    'CH${i + 1}',
                                    selected: i == channel,
                                    onTap: _recording
                                        ? null
                                        : () => setState(() => _channel = i),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _Crt(
                                label: source,
                                recording: _recording,
                                timecode: _timecode(),
                                live: devices.isNotEmpty,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PixelPanel(
                            title: 'LEVELS',
                            trailing: const DemoBadge(
                              label: 'SIM',
                              onTitleBar: true,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text('L', style: context.pixel()),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SegmentBar(
                                        value: _left,
                                        segments: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text('R', style: context.pixel()),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SegmentBar(
                                        value: _right,
                                        segments: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: PixelPanel(
                              title: 'SETUP',
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'RES',
                                      style: context.pixel(color: p.inkDim),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final r in const ['720P', '1080P'])
                                          PixelChip(
                                            r,
                                            selected: r == _res,
                                            onTap: _recording
                                                ? null
                                                : () =>
                                                      setState(() => _res = r),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'FPS',
                                      style: context.pixel(color: p.inkDim),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final f in const ['30', '60'])
                                          PixelChip(
                                            f,
                                            selected: f == _fps,
                                            onTap: _recording
                                                ? null
                                                : () =>
                                                      setState(() => _fps = f),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    PixelChip(
                                      _audio ? 'AUDIO ON' : 'AUDIO OFF',
                                      selected: _audio,
                                      onTap: _recording
                                          ? null
                                          : () => setState(
                                              () => _audio = !_audio,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PixelKey(
                      glyph: PixelGlyph.record,
                      label: 'REC',
                      compact: true,
                      selected: _recording && !_paused,
                      onPressed: _recording
                          ? null
                          : () {
                              if (devices.isEmpty) {
                                showNotWired(
                                  context,
                                  'Recording without a phone (connect one to try the simulation)',
                                );
                                return;
                              }
                              _record();
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelKey(
                      glyph: PixelGlyph.pause,
                      label: 'PAUSE',
                      compact: true,
                      selected: _paused,
                      onPressed: _recording
                          ? () => setState(() => _paused = !_paused)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelKey(
                      glyph: PixelGlyph.stop,
                      label: 'STOP',
                      compact: true,
                      onPressed: _recording ? _stop : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelKey(
                      glyph: PixelGlyph.camera,
                      label: 'SNAP',
                      compact: true,
                      onPressed: () => showNotWired(context, 'Screenshot'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 2,
                child: PixelPanel(
                  title: 'CLIPS',
                  trailing: const DemoBadge(label: 'DEMO', onTitleBar: true),
                  padding: const EdgeInsets.all(6),
                  child: ListView(
                    children: [
                      for (final c in _clips)
                        InkWell(
                          onTap: () =>
                              showNotWired(context, 'Playing ${c.name}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Row(
                              children: [
                                const PixelIcon(PixelGlyph.play, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(c.name, style: context.body()),
                                ),
                                Text(c.length, style: context.body()),
                                const SizedBox(width: 14),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    c.size,
                                    textAlign: TextAlign.end,
                                    style: context.body(color: p.inkDim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The monitor tube: colour-bar test pattern (in ink shades) when there is
/// nothing to show, with timecode and source overlaid.
class _Crt extends StatelessWidget {
  const _Crt({
    required this.label,
    required this.recording,
    required this.timecode,
    required this.live,
  });

  final String label;
  final bool recording;
  final String timecode;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Container(
      decoration: BoxDecoration(
        color: p.screen,
        border: Border.all(color: p.ink, width: 3),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _BarsPainter(p.ink, dim: live)),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              color: p.screen,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(label, style: context.pixel()),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              color: p.screen,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(timecode, style: context.pixel(size: 16)),
            ),
          ),
          if (!recording)
            Center(
              child: Container(
                color: p.screen,
                padding: const EdgeInsets.all(6),
                child: Blink(
                  child: Text(
                    live ? 'READY' : 'NO SIGNAL',
                    style: context.pixel(size: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.color, {required this.dim});
  final Color color;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 8;
    final w = size.width / bars;
    final h = size.height * 0.7;
    for (var i = 0; i < bars; i++) {
      final paint = Paint()
        ..isAntiAlias = false
        ..color = color.withValues(
          alpha: (dim ? 0.1 : 0.14) + i * (dim ? 0.04 : 0.1),
        );
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w, h), paint);
    }
    // Lower strip: a dither ramp.
    final dither = Paint()
      ..isAntiAlias = false
      ..color = color.withValues(alpha: 0.2);
    for (double y = h; y < size.height; y += 4) {
      for (double x = ((y - h) ~/ 4).isEven ? 0 : 4; x < size.width; x += 8) {
        canvas.drawRect(Rect.fromLTWH(x, y, 4, 4), dither);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.dim != dim;
}
