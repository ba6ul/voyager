import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts a process. Defaults to [Process.start]; tests substitute a fake.
typedef ProcessStarter = Future<Process> Function(
    String executable, List<String> arguments);

/// Manages the lifecycle of standalone `scrcpy` processes.
///
/// This class acts as a single-instance process guard per connected device,
/// tracking active window instances by their hardware serial numbers.
/// This prevents redundant window spawning when upstream device-tracking streams 
/// re-emit hardware state snapshots.
///
/// Lifecycle & Stream Management:
/// 1. Launch: Spawns the native binary with combined base and contextual flags.
/// 2. Isolation: Pipes and discards standard output while filtering error streams.
/// 3. Cleanup: Synchronizes internal state hooks natively upon process exit.
class ScrcpyLauncher {
  ScrcpyLauncher({
    required this.scrcpyPath,
    this.baseArgs = const [],
    this.onExit,
    ProcessStarter? processStarter,
  }) : _start = processStarter ?? Process.start;

  final String scrcpyPath;
  final List<String> baseArgs;

  /// Called when a launched scrcpy process exits, whether the daemon asked
  /// it to (`stop`/`stopAll`) or it died on its own (e.g. the adb transport
  /// dropping out from under it during a `tcpip` restart).
  final void Function(String serial, int exitCode)? onExit;

  final ProcessStarter _start;

  final Map<String, Process> _running = {};

  /// Serials whose scrcpy is being started: the slot is reserved before the
  /// first `await`, so a second launch for the same serial cannot slip in
  /// while [Process.start] is still pending.
  final Set<String> _starting = {};

  bool isRunning(String serial) =>
      _running.containsKey(serial) || _starting.contains(serial);

  /// Launches scrcpy for [serial]. Returns false if one is already running
  /// (or being started) for that device.
  Future<bool> launch(
    String serial, {
    String? windowTitle,
    List<String> extraArgs = const [],
  }) async {
    if (isRunning(serial)) return false;

    final args = <String>[
      '-s',
      serial,
      if (windowTitle != null) '--window-title=$windowTitle',
      ...baseArgs,
      ...extraArgs,
    ];

    _starting.add(serial);
    final Process process;
    try {
      process = await _start(scrcpyPath, args);
    } finally {
      _starting.remove(serial);
    }
    _running[serial] = process;

    // Surface scrcpy's own errors in the daemon log, drop the noise.
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.contains('ERROR')) stderr.writeln('[scrcpy $serial] $line');
    });
    process.stdout.drain<void>();

    unawaited(process.exitCode.then((code) {
      // The entry under [serial] may belong to a newer process by now (stop()
      // followed by launch()). Only clear and report it if it is still ours;
      // a superseded process must not make a live mirror look closed.
      final current = _running[serial];
      final superseded = current != null && !identical(current, process);
      if (!superseded) _running.remove(serial);
      stdout.writeln('[x] scrcpy for $serial closed (exit $code)');
      if (!superseded) onExit?.call(serial, code);
    }));
    return true;
  }

  /// Closes the scrcpy window for [serial], if any.
  void stop(String serial) => _running.remove(serial)?.kill();

  void stopAll() {
    for (final process in _running.values) {
      process.kill();
    }
    _running.clear();
  }
}
