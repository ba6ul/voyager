import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_icon.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import '../../devices/presentation/cubit/device_list_state.dart';

/// Flutter / App Development: a small IDE. Projects and installed apps on
/// the left, a run configuration and a log on the right. Everything here is
/// a mock-up: Run starts a scripted SIMULATION so the workspace can be felt
/// before project discovery and `flutter run` are wired up.
class FlutterWorkspace extends StatefulWidget {
  const FlutterWorkspace({super.key});

  @override
  State<FlutterWorkspace> createState() => _FlutterWorkspaceState();
}

class _Project {
  const _Project(this.name, this.path, this.sdk);
  final String name;
  final String path;
  final String sdk;
}

const _projects = [
  _Project('voyager_ui', r'D:\dev\voyager\packages\ui', '3.32'),
  _Project('habit_tracker', r'D:\dev\habit_tracker', '3.32'),
  _Project('weather_demo', r'D:\dev\weather_demo', '3.27'),
];

const _apps = [
  ('Photos', 'com.google.android.apps.photos'),
  ('Calculator', 'com.google.android.calculator'),
  ('habit_tracker', 'com.example.habit_tracker'),
  ('Settings', 'com.android.settings'),
];

const _script = [
  'Launching lib/main.dart in debug mode...',
  "Running Gradle task 'assembleDebug'...",
  'Built build/app/outputs/flutter-apk/app-debug.apk',
  'Installing app-debug.apk...',
  'Syncing files to device...',
  'Flutter run key commands.  r Hot reload.  R Hot restart.  q Quit.',
  'A Dart VM Service is available (simulated).',
];

class _FlutterWorkspaceState extends State<FlutterWorkspace> {
  int _project = 0;
  String _mode = 'DEBUG';
  bool _running = false;
  int _reloads = 0;
  final _log = <String>[
    'flutter run output appears here.',
    'This is a simulation: nothing is built or installed yet.',
  ];
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _add(String line) {
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _run(String target) {
    if (_running) return;
    setState(() {
      _running = true;
      _reloads = 0;
      _log.clear();
      _add('[SIM] ${_projects[_project].name} on $target ($_mode)');
    });
    var i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (i >= _script.length) {
        t.cancel();
        _add('[SIM] Application running.');
        return;
      }
      _add(_script[i++]);
    });
  }

  void _stop() {
    _timer?.cancel();
    if (!_running) return;
    setState(() => _running = false);
    _add('[SIM] Application finished.');
  }

  void _reload(bool restart) {
    if (!_running) return;
    _reloads++;
    _add(
      restart
          ? '[SIM] Restarted application in ${400 + _reloads * 7}ms.'
          : '[SIM] Reloaded 1 of 412 libraries in ${120 + _reloads * 3}ms.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PixelPanel(
                    title: 'PROJECTS',
                    trailing: const DemoBadge(label: 'DEMO', onTitleBar: true),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            children: [
                              for (var i = 0; i < _projects.length; i++)
                                _ListRow(
                                  glyph: PixelGlyph.folder,
                                  title: _projects[i].name,
                                  subtitle: 'SDK ${_projects[i].sdk}',
                                  selected: i == _project,
                                  onTap: () => setState(() => _project = i),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton(
                          onPressed: () =>
                              showNotWired(context, 'Open a project'),
                          child: const Text('+ OPEN'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PixelPanel(
                    title: 'APPS ON UNIT',
                    trailing: const DemoBadge(label: 'DEMO', onTitleBar: true),
                    padding: const EdgeInsets.all(6),
                    child: ListView(
                      children: [
                        for (final (name, id) in _apps)
                          _ListRow(
                            glyph: PixelGlyph.file,
                            title: name,
                            subtitle: id,
                            onTap: () => showNotWired(context, 'Launch $name'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BlocBuilder<DeviceListCubit, DeviceListState>(
                  buildWhen: (a, b) => a.devices != b.devices,
                  builder: (context, state) {
                    final ready = state.devices
                        .where((d) => d.isReady)
                        .toList();
                    final target = ready.isEmpty
                        ? 'no unit (demo target)'
                        : (ready.first.model ?? ready.first.serial);
                    return PixelPanel(
                      title: 'RUN CONFIG',
                      trailing: PixelBadge(
                        _running ? 'RUNNING' : 'IDLE',
                        inverse: true,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReadoutRow('PROJECT', _projects[_project].name),
                          ReadoutRow('TARGET', target),
                          ReadoutRow('ENTRY', 'lib/main.dart'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final m in const [
                                'DEBUG',
                                'PROFILE',
                                'RELEASE',
                              ]) ...[
                                PixelChip(
                                  m,
                                  selected: m == _mode,
                                  onTap: _running
                                      ? null
                                      : () => setState(() => _mode = m),
                                ),
                                const SizedBox(width: 6),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: _running ? null : () => _run(target),
                                child: const Text('RUN'),
                              ),
                              OutlinedButton(
                                onPressed: _running
                                    ? () => _reload(false)
                                    : null,
                                child: const Text('RELOAD'),
                              ),
                              OutlinedButton(
                                onPressed: _running
                                    ? () => _reload(true)
                                    : null,
                                child: const Text('RESTART'),
                              ),
                              OutlinedButton(
                                onPressed: _running ? _stop : null,
                                child: const Text('STOP'),
                              ),
                              OutlinedButton(
                                onPressed: () =>
                                    showNotWired(context, 'DevTools'),
                                child: const Text('DEVTOOLS'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PixelPanel(
                    title: 'RUN LOG',
                    trailing: const DemoBadge(
                      label: 'SIMULATION',
                      onTitleBar: true,
                    ),
                    padding: EdgeInsets.zero,
                    child: Container(
                      color: p.screen,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(8),
                        itemCount: _log.length + (_running ? 1 : 0),
                        itemBuilder: (_, i) => i == _log.length
                            ? const Blink(child: Text('█'))
                            : Text(
                                _log[i],
                                style: context.body(
                                  size: 19,
                                  color: _log[i].startsWith('[SIM]')
                                      ? p.ink
                                      : p.inkDim,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final PixelGlyph glyph;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final fg = selected ? p.screen : p.ink;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: p.ink.withValues(alpha: 0.12),
        child: Container(
          color: selected ? p.ink : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              PixelIcon(glyph, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(size: 21, color: fg),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: 16,
                        color: selected ? p.screen : p.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
