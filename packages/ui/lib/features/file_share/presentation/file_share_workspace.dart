import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';

/// File Sharing: a transfer utility in the style of a dual-pane file
/// manager. Both panes and the queue are mock-ups (marked DEMO); SEND and
/// PULL queue a simulated transfer so the flow can be felt.
class FileShareWorkspace extends StatefulWidget {
  const FileShareWorkspace({super.key});

  @override
  State<FileShareWorkspace> createState() => _FileShareWorkspaceState();
}

class _Entry {
  const _Entry(this.name, this.size, {this.folder = false});
  final String name;
  final String size;
  final bool folder;
}

const _pc = [
  _Entry('..', '', folder: true),
  _Entry('screenshots', '', folder: true),
  _Entry('app-release.apk', '21.4 MB'),
  _Entry('wallpaper.png', '2.1 MB'),
  _Entry('notes.txt', '3 KB'),
  _Entry('demo-clip.mp4', '48.0 MB'),
];

const _phone = [
  _Entry('..', '', folder: true),
  _Entry('DCIM', '', folder: true),
  _Entry('Download', '', folder: true),
  _Entry('IMG_2041.jpg', '3.6 MB'),
  _Entry('IMG_2042.jpg', '3.4 MB'),
  _Entry('voice_note.m4a', '812 KB'),
];

class _Transfer {
  _Transfer(this.name, this.toPhone);
  final String name;
  final bool toPhone;
  double progress = 0;
  bool get done => progress >= 1;
}

class _FileShareWorkspaceState extends State<FileShareWorkspace> {
  final _pcSelected = <int>{};
  final _phoneSelected = <int>{};
  final _queue = <_Transfer>[];
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enqueue(bool toPhone) {
    final source = toPhone ? _pc : _phone;
    final selected = toPhone ? _pcSelected : _phoneSelected;
    final files = [
      for (final i in selected)
        if (!source[i].folder) source[i].name,
    ];
    if (files.isEmpty) {
      showNotWired(context, 'Folders and an empty selection');
      return;
    }
    setState(() {
      for (final f in files) {
        _queue.add(_Transfer(f, toPhone));
      }
      selected.clear();
    });
    _timer ??= Timer.periodic(const Duration(milliseconds: 120), (t) {
      var active = false;
      setState(() {
        for (final item in _queue) {
          if (!item.done) {
            item.progress = (item.progress + 0.04).clamp(0, 1);
            active = true;
            break; // one at a time, like a real queue
          }
        }
      });
      if (!active) {
        t.cancel();
        _timer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => showNotWired(context, 'Drag and drop'),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: p.inkDim, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned.fill(
                    child: DitherFill(cell: 2, opacity: 0.1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const PixelIcon(PixelGlyph.down, size: 16),
                      const SizedBox(width: 10),
                      Container(
                        color: p.screen,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'DROP FILES HERE TO SEND',
                          style: context.pixel(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const DemoBadge(label: 'SOON'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Pane(
                    title: 'PC',
                    path: r'C:\Users\you\Downloads',
                    entries: _pc,
                    selected: _pcSelected,
                    onChanged: () => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PixelKey(
                        glyph: PixelGlyph.up,
                        label: 'SEND',
                        compact: true,
                        tooltip: 'Send the selected PC files to the phone',
                        onPressed: () => _enqueue(true),
                      ),
                      const SizedBox(height: 14),
                      PixelKey(
                        glyph: PixelGlyph.down,
                        label: 'PULL',
                        compact: true,
                        tooltip: 'Pull the selected phone files to the PC',
                        onPressed: () => _enqueue(false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _Pane(
                    title: 'PHONE',
                    path: '/sdcard/Download',
                    entries: _phone,
                    selected: _phoneSelected,
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: PixelPanel(
              title: 'QUEUE',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DemoBadge(label: 'SIMULATION', onTitleBar: true),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () =>
                        setState(() => _queue.removeWhere((t) => t.done)),
                    child: Text(
                      'CLEAR DONE',
                      style: context.pixel(color: p.screen),
                    ),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: _queue.isEmpty
                  ? Center(
                      child: Text(
                        'Queue empty. Select files and press SEND or PULL.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      children: [
                        for (final t in _queue)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                PixelIcon(
                                  t.toPhone ? PixelGlyph.up : PixelGlyph.down,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    t.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.body(),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: SegmentBar(
                                    value: t.progress,
                                    height: 14,
                                  ),
                                ),
                                SizedBox(
                                  width: 56,
                                  child: Text(
                                    t.done
                                        ? 'DONE'
                                        : '${(t.progress * 100).round()}%',
                                    textAlign: TextAlign.end,
                                    style: context.pixel(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.title,
    required this.path,
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final String path;
  final List<_Entry> entries;
  final Set<int> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return PixelPanel(
      title: title,
      trailing: const DemoBadge(label: 'DEMO', onTitleBar: true),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.screen,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: 18, color: p.inkDim),
            ),
          ),
          Container(height: 2, color: p.ink),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final e = entries[i];
                  final on = selected.contains(i);
                  final fg = on ? p.screen : p.ink;
                  return InkWell(
                    onTap: () {
                      if (e.name == '..') return;
                      if (e.folder) {
                        showNotWired(context, 'Opening folders');
                        return;
                      }
                      on ? selected.remove(i) : selected.add(i);
                      onChanged();
                    },
                    child: Container(
                      color: on ? p.ink : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          PixelIcon(
                            e.folder ? PixelGlyph.folder : PixelGlyph.file,
                            size: 16,
                            color: fg,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.body(color: fg),
                            ),
                          ),
                          Text(
                            e.size,
                            style: context.body(
                              size: 18,
                              color: on ? p.screen : p.inkDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
