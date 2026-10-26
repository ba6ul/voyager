import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_ipc/scrcpy_ipc.dart';
import 'package:test/test.dart';

/// Runs the real daemon (`bin/daemon.dart`) as a child process, isolated from
/// the machine it runs on:
/// - `ANDROID_ADB_SERVER_PORT` points it at a fake adb server, so the real adb
///   server on 5037 is never contacted, stopped or restarted;
/// - `APPDATA` and `HOME` point at a temporary folder, so the developer's
///   real `config.json` and known-devices file are never read or written;
/// - the IPC port is a free port chosen for this run.
class DaemonHarness {
  DaemonHarness._(this._process, this._dir, this.ipcPort);

  final Process _process;
  final Directory _dir;
  final int ipcPort;

  final List<String> log = [];
  bool _exited = false;
  int? exitCode;

  /// True while the daemon process is still alive.
  bool get isAlive => !_exited;

  static Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Starts the daemon against the adb server on [adbPort].
  ///
  /// [scrcpyPath] defaults to a path that does not exist. [adbPath], if given,
  /// is passed as the daemon's first argument (the adb binary it would run to
  /// start a server).
  static Future<DaemonHarness> start({
    required int adbPort,
    bool autoLaunch = false,
    String? scrcpyPath,
    String? adbPath,
  }) async {
    final dir = Directory.systemTemp.createTempSync('daemon_harness');
    final ipcPort = await freePort();
    final configDir = Directory('${dir.path}${Platform.pathSeparator}scrcpy_gui')
      ..createSync(recursive: true);
    File('${configDir.path}${Platform.pathSeparator}config.json')
        .writeAsStringSync(jsonEncode({
      'adbPath': 'adb',
      'scrcpyPath': scrcpyPath ??
          '${dir.path}${Platform.pathSeparator}no-such-dir${Platform.pathSeparator}scrcpy',
      'autoLaunch': autoLaunch,
      'scrcpyArgs': <String>[],
      'ipcPort': ipcPort,
    }));

    final process = await Process.start(
      Platform.resolvedExecutable,
      ['bin/daemon.dart', if (adbPath != null) adbPath],
      workingDirectory: Directory.current.path,
      environment: {
        'ANDROID_ADB_SERVER_PORT': '$adbPort',
        'APPDATA': dir.path,
        'HOME': dir.path,
      },
    );
    final harness = DaemonHarness._(process, dir, ipcPort);
    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(harness.log.add);
    }
    unawaited(process.exitCode.then((code) {
      harness._exited = true;
      harness.exitCode = code;
    }));
    return harness;
  }

  /// Waits until [count] log lines contain [text] (once by default); fails
  /// the test after [timeout]. Waiting for 2 shows that something repeats.
  Future<String> waitForLog(String text,
      {int count = 1, Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final matches = log.where((line) => line.contains(text)).toList();
      if (matches.length >= count) return matches.last;
      if (_exited) {
        fail('daemon exited (code $exitCode) before logging "$text". '
            'Log:\n${log.join('\n')}');
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('"$text" not logged $count time(s) within $timeout. Log:\n${log.join('\n')}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  /// Sends a line to the daemon's stdin, like typing a key in its terminal.
  void type(String line) => _process.stdin.writeln(line);

  /// Asks the daemon for its device list over IPC. Completing at all proves it
  /// is alive and serving requests.
  Future<List<Map<String, dynamic>>> listDevices() async {
    final client = IpcClient();
    await client.connect(port: ipcPort);
    try {
      final result = await client.send(IpcCommands.listDevices);
      return (result.data['devices'] as List).cast<Map<String, dynamic>>();
    } finally {
      await client.close();
    }
  }

  Future<void> stop() async {
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      _process.kill(ProcessSignal.sigkill);
      return -1;
    });
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows may still hold the folder for a moment; it is a temp folder.
    }
  }
}
