import 'dart:async';
import 'dart:convert';

import '../../../core/daemon/daemon_launcher.dart';
import '../../devices/domain/entities/device.dart';
import '../../devices/presentation/cubit/device_list_cubit.dart';
import '../../devices/presentation/cubit/device_list_state.dart';

/// One line of console output.
class ConsoleLine {
  const ConsoleLine(this.text, {this.note = false, this.input = false});

  final String text;

  /// Secondary text (hints, "coming soon").
  final bool note;

  /// The user's own command, echoed.
  final bool input;
}

/// The console's commands, on top of what the daemon already offers over IPC.
/// `clear` is handled by the panel. [print] receives each output line; a
/// command's lines may arrive after it started (restart waits for the daemon).
class ConsoleCommands {
  ConsoleCommands(this._cubit, this._launcher, this._print);

  final DeviceListCubit _cubit;
  final DaemonLauncher? _launcher;
  final void Function(ConsoleLine line) _print;

  static const help = [
    ConsoleLine('devices          list units'),
    ConsoleLine('play [unit]      open a mirror'),
    ConsoleLine('stop [unit]      close its mirror'),
    ConsoleLine('stopall          close every mirror'),
    ConsoleLine('wireless [unit]  go wireless (USB phone)'),
    ConsoleLine('handoff [unit]   move a mirror to wireless'),
    ConsoleLine('usb [unit]       drop a wireless address'),
    ConsoleLine('config           show the service settings'),
    ConsoleLine('restart          restart the service'),
    ConsoleLine('quit             stop the service'),
    ConsoleLine('clear            wipe the screen'),
    ConsoleLine('[unit] is a serial or part of one; default: the first '
        'ready unit.', note: true),
    ConsoleLine('adb and shell commands: coming soon.', note: true),
  ];

  void _out(String text, {bool note = false}) =>
      _print(ConsoleLine(text, note: note));

  DeviceListState get _state => _cubit.state;

  /// The unit a command is about: [arg] matched against serials and model
  /// names, or the first ready one. Prints why and returns null if none.
  Device? _unit(String? arg) {
    final devices = _state.devices;
    if (devices.isEmpty) {
      _out('no units connected', note: true);
      return null;
    }
    if (arg == null) {
      final ready = devices.where((d) => d.isReady);
      if (ready.isEmpty) {
        _out('no unit is ready', note: true);
        return null;
      }
      return ready.first;
    }
    final needle = arg.toLowerCase();
    final matches = devices
        .where((d) =>
            d.serial.toLowerCase().contains(needle) ||
            (d.model?.toLowerCase().contains(needle) ?? false))
        .toList();
    if (matches.length == 1) return matches.first;
    _out(matches.isEmpty ? "no unit matches '$arg'" : "'$arg' matches "
        '${matches.length} units; be more specific', note: true);
    return null;
  }

  /// Runs [line]. Returns once it has finished (restart: once the service is
  /// back or gave up).
  Future<void> run(String line) async {
    final parts = line.trim().split(RegExp(r'\s+'));
    final command = parts.first.toLowerCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : null;
    try {
      switch (command) {
        case 'help':
          for (final l in help) {
            _print(l);
          }
        case 'devices':
          _devices();
        case 'play':
          final d = _unit(arg);
          if (d == null) return;
          await _cubit.play(d.serial);
          _report(d, 'mirror requested for ${d.model ?? d.serial}');
        case 'stop':
          final d = _unit(arg);
          if (d == null) return;
          await _cubit.stop(d.serial);
          _report(d, 'closed the mirror for ${d.model ?? d.serial}');
        case 'stopall':
          await _cubit.stopAll();
          _out('closed every mirror');
        case 'wireless':
          final d = _unit(arg);
          if (d == null) return;
          await _cubit.goWireless(d.serial);
          _report(d, 'go wireless started; watch the unit card for progress');
        case 'handoff':
          final d = _unit(arg);
          if (d == null) return;
          await _cubit.handoff(d.serial);
          _report(d, 'handoff started; watch the unit card for progress');
        case 'usb':
          final d = _unit(arg);
          if (d == null) return;
          await _cubit.usbMode(d.serial);
          _out('${d.model ?? d.serial} set back to USB only');
        case 'config':
          final config = await _cubit.daemonConfig();
          for (final l in const JsonEncoder.withIndent('  ')
              .convert(config)
              .split('\n')) {
            _out(l);
          }
        case 'quit':
          await _cubit.quitDaemon();
          _out('service stopped. Use Start service to bring it back.',
              note: true);
        case 'restart':
          await _restart();
        case 'adb' || 'shell' || 'logcat' || 'install' || 'push' || 'pull':
          _out("'$command': coming soon. Not wired to the phone yet.",
              note: true);
        default:
          _out("unknown command '$command'. Type help.", note: true);
      }
    } catch (e) {
      _out('$command failed: $e', note: true);
    }
  }

  void _devices() {
    if (_state.devices.isEmpty) {
      _out('no units');
      return;
    }
    for (final d in _state.devices) {
      _out('${d.serial}  ${d.state.name}  ${d.transport.name}'
          '${d.mirroring ? '  mirroring' : ''}');
    }
  }

  /// Prints [ok], unless the cubit recorded a failure for [d] (it shows
  /// failures on the device row and keeps the text).
  void _report(Device d, String ok) {
    final message = _cubit.state.actions[d.serial]?.message;
    _out(message ?? ok, note: message != null);
  }

  Future<bool> _waitFor(DaemonConnection wanted, Duration timeout) async {
    if (_cubit.state.connection == wanted) return true;
    try {
      await _cubit.stream
          .firstWhere((s) => s.connection == wanted)
          .timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _restart() async {
    final launcher = _launcher;
    if (launcher == null) {
      _out('restart is not available here', note: true);
      return;
    }
    _out('stopping the service...');
    await _cubit.quitDaemon();
    if (!await _waitFor(
        DaemonConnection.unreachable, const Duration(seconds: 8))) {
      _out('the service did not stop', note: true);
      return;
    }
    _out('starting the service...');
    final error = await launcher.start();
    if (error != null) {
      _out(error, note: true);
      return;
    }
    _out(await _waitFor(DaemonConnection.connected, const Duration(seconds: 30))
        ? 'service is back'
        : 'the service did not answer; use Start service',
        note: false);
  }
}
