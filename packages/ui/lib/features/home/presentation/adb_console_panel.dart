import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/daemon/daemon_launcher.dart';
import '../../../core/theme/retro_theme.dart';
import '../../../core/widgets/pixel_panel.dart';
import '../../../core/widgets/retro_widgets.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import 'console_commands.dart';

/// A terminal-style console for the daemon: list units, play, stop, go
/// wireless, restart the service and so on (see [ConsoleCommands.help]).
/// Raw adb and shell commands are not wired yet and say so.
class AdbConsolePanel extends StatefulWidget {
  const AdbConsolePanel({super.key, this.daemonLauncher});

  /// Needed for `restart`.
  final DaemonLauncher? daemonLauncher;

  @override
  State<AdbConsolePanel> createState() => _AdbConsolePanelState();
}

class _AdbConsolePanelState extends State<AdbConsolePanel> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _lines = <ConsoleLine>[
    const ConsoleLine('VOYAGER SHELL v0.2'),
    const ConsoleLine("Type 'help' for the commands.", note: true),
  ];
  final _history = <String>[];
  int _historyAt = 0;
  late final ConsoleCommands _commands;

  @override
  void initState() {
    super.initState();
    _commands = ConsoleCommands(
      context.read<DeviceListCubit>(),
      widget.daemonLauncher,
      _add,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _add(ConsoleLine line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _submit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty) return;
    _history.add(command);
    _historyAt = _history.length;
    _input.clear();
    _focus.requestFocus();
    if (command.toLowerCase() == 'clear') {
      setState(_lines.clear);
      return;
    }
    _add(ConsoleLine('> $command', input: true));
    await _commands.run(command);
  }

  /// Up and down walk through earlier commands.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _history.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyAt = (_historyAt - 1).clamp(0, _history.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _historyAt = (_historyAt + 1).clamp(0, _history.length);
    } else {
      return KeyEventResult.ignored;
    }
    final text = _historyAt < _history.length ? _history[_historyAt] : '';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return PixelPanel(
      title: 'CONSOLE',
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
                      color: line.note ? p.inkDim : p.ink,
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
                  child: Focus(
                    onKeyEvent: _onKey,
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
                      onSubmitted: _submit,
                    ),
                  ),
                ),
                for (final c in const ['devices', 'help'])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: PixelChip(c, selected: false, onTap: () => _submit(c)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
