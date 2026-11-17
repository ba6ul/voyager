import 'dart:io';

/// Starts the background service (the daemon) on this PC.
abstract class DaemonLauncher {
  /// Starts the daemon. Returns null once it has been started, or a plain
  /// sentence saying why it could not be. Starting is not the same as
  /// reachable: the UI's connection retries on its own and picks it up.
  Future<String?> start();
}

/// Runs `dart run bin/daemon.dart` from the repository's `packages/daemon`,
/// found by walking up from the app. This is the development setup; the
/// installer will bundle the daemon and replace it.
class LocalDaemonLauncher implements DaemonLauncher {
  const LocalDaemonLauncher();

  /// The `packages/daemon` folder above [from], or null.
  static Directory? findDaemonDir(Directory from) {
    var dir = from.absolute;
    for (var i = 0; i < 10; i++) {
      final candidate =
          Directory('${dir.path}${Platform.pathSeparator}packages'
              '${Platform.pathSeparator}daemon');
      if (File('${candidate.path}${Platform.pathSeparator}bin'
              '${Platform.pathSeparator}daemon.dart')
          .existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  @override
  Future<String?> start() async {
    final dir = findDaemonDir(File(Platform.resolvedExecutable).parent) ??
        findDaemonDir(Directory.current);
    if (dir == null) {
      return 'Could not find the daemon folder (packages/daemon) next to '
          'this app.';
    }
    try {
      // Detached: it keeps running if this window's process ends. A shell is
      // needed because `dart` is a .bat file on some Flutter installs.
      await Process.start(
        'dart',
        const ['run', 'bin/daemon.dart'],
        workingDirectory: dir.path,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return null;
    } on ProcessException catch (e) {
      return 'Could not run "dart": ${e.message}. Is the Dart SDK on your '
          'PATH?';
    }
  }
}
