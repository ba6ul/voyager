import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';

/// A terminal-style console. It does not talk to the phone yet: typed
/// commands are echoed and answered with a "not wired" line. `devices` is
/// real (it lists what the daemon reports); `help` and `clear` work.
class AdbConsolePanel extends StatefulWidget {
  const AdbConsolePanel({super.key});

  @override
  State<AdbConsolePanel> createState() => _AdbConsolePanelState();
}

enum _Kind { input, output, note }

class _Line {
  const _Line(this.text, this.kind);
  final String text;
  final _Kind kind;
}

class _AdbConsolePanelState extends State<AdbConsolePanel> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _lines = <_Line>[
    const _Line('VOYAGER SHELL v0.1', _Kind.output),
    const _Line(
      "Type 'help'. Commands do not reach the phone yet.",
      _Kind.note,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String raw) {
    final command = raw.trim();
    if (command.isEmpty) return;
    final state = context.read<DeviceListCubit>().state;
    setState(() {
      _lines.add(_Line('> $command', _Kind.input));
      switch (command) {
        case 'clear':
          _lines.clear();
        case 'help':
          _lines.addAll(const [
            _Line('help      this list', _Kind.output),
            _Line('devices   units the daemon sees', _Kind.output),
            _Line('clear     wipe the screen', _Kind.output),
            _Line('anything else: coming soon', _Kind.note),
          ]);
        case 'devices':
          if (state.devices.isEmpty) {
            _lines.add(const _Line('no units', _Kind.output));
          } else {
            for (final d in state.devices) {
              _lines.add(_Line('${d.serial}\t${d.state.name}', _Kind.output));
            }
          }
        default:
          _lines.add(
            _Line(
              "'${command.split(' ').first}' is not wired yet: "
              'coming soon.',
              _Kind.note,
            ),
          );
      }
    });
    _input.clear();
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return PixelPanel(
      title: 'ADB CONSOLE',
      trailing: const DemoBadge(label: 'SOON', onTitleBar: true),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: Container(
              color: p.screen,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final line = _lines[i];
                  return Text(
                    line.text,
                    style: context.body(
                      size: 19,
                      color: line.kind == _Kind.note ? p.inkDim : p.ink,
                    ),
                  );
                },
              ),
            ),
          ),
          Container(height: 2, color: p.ink),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text('>', style: context.pixel(size: 8)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    style: context.body(),
                    cursorWidth: 8,
                    cursorHeight: 16,
                    decoration: const InputDecoration(
                      hintText: 'type a command',
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                    onSubmitted: _run,
                  ),
                ),
                for (final c in const ['devices', 'help'])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: PixelChip(c, selected: false, onTap: () => _run(c)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
