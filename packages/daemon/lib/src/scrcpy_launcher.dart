import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  });

  final String scrcpyPath;
  final List<String> baseArgs;

  /// Called when a launched scrcpy process exits, whether the daemon asked
  /// it to (`stop`/`stopAll`) or it died on its own (e.g. the adb transport
  /// dropping out from under it during a `tcpip` restart).
  final void Function(String serial, int exitCode)? onExit;

  final Map<String, Process> _running = {};

  bool isRunning(String serial) => _running.containsKey(serial);

  /// Launches scrcpy for [serial]. Returns false if one is already running for that device.
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

    final process = await Process.start(scrcpyPath, args);
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
      _running.remove(serial);
      stdout.writeln('[x] scrcpy for $serial closed (exit $code)');
      onExit?.call(serial, code);
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
