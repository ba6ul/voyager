import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts a process. Defaults to [Process.start]; tests substitute a fake.
typedef ProcessStarter = Future<Process> Function(
    String executable, List<String> arguments);

/// What [ScrcpyLauncher.launch] did. A launch that cannot start scrcpy at all
/// (for example a missing binary) throws instead.
enum LaunchResult {
  /// A new scrcpy process was started for the serial.
  started,

  /// A mirror for the serial is already running (or being started); nothing
  /// was done, and the device is mirrored as wanted.
  alreadyRunning,
}

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

  /// Serials that [stop]/[stopAll] was asked to close while their process was
  /// still being started; applied the moment the process exists.
  final Set<String> _stopRequested = {};

  bool isRunning(String serial) =>
      _running.containsKey(serial) || _starting.contains(serial);

  /// Launches scrcpy for [serial]. Returns [LaunchResult.alreadyRunning] if
  /// one is already running (or being started) for that device, and throws if
  /// the process cannot be started.
  Future<LaunchResult> launch(
    String serial, {
    String? windowTitle,
    List<String> extraArgs = const [],
  }) async {
    if (_starting.contains(serial)) {
      // A launch is already in flight. If a stop arrived meanwhile, this later
      // request wins and the mirror stays.
      _stopRequested.remove(serial);
      return LaunchResult.alreadyRunning;
    }
    if (_running.containsKey(serial)) return LaunchResult.alreadyRunning;

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
    // A stop that arrived while the process was starting had nothing to kill
    // yet; honour it now instead of leaving a mirror the caller closed. The
    // process is then not tracked, and its exit is still reported below.
    if (_stopRequested.remove(serial)) {
      process.kill();
    } else {
      _running[serial] = process;
    }

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
    return LaunchResult.started;
  }

  /// Closes the scrcpy window for [serial], if any. If one is still being
  /// started, it is closed as soon as it exists.
  void stop(String serial) {
    if (_starting.contains(serial)) _stopRequested.add(serial);
    _running.remove(serial)?.kill();
  }

  void stopAll() {
    _stopRequested.addAll(_starting);
    for (final process in _running.values) {
      process.kill();
    }
    _running.clear();
  }
}
