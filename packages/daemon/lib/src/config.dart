import 'dart:convert';
import 'dart:io';

// 1. Define the default fallback port constant
const int kDefaultIpcPort = 38765;

/// Manages persistent configuration for the background daemon.
///
/// Settings are serialized as JSON and stored within the platform's user 
/// application directory (e.g., `%APPDATA%\scrcpy_gui\config.json` on Windows).
///
/// Lifecycle:
/// 1. First Run: Generates and persists auto-detected system defaults.
/// 2. Runtime: Read by the daemon to locate binaries and apply launch arguments.
/// 3. Flutter Integration: Overwritten by the frontend GUI when user settings change.
class DaemonConfig {
  DaemonConfig({
    required this.adbPath,
    required this.scrcpyPath,
    required this.autoLaunch,
    required this.ipcPort,
    required this.scrcpyArgs,
  });

  /// Path to adb.exe, or just `adb` to use PATH.
  final String adbPath;

  /// Path to scrcpy.exe, or just `scrcpy` to use PATH.
  final String scrcpyPath;

  /// Milestone 2 behavior: launch scrcpy the moment a ready device appears.
  /// The popup UI will later set this to false and take over.
  final bool autoLaunch;

  final int ipcPort; // default kDefaultIpcPort (38765)

  /// Extra flags passed to every scrcpy launch,
  /// e.g. ["--stay-awake", "--turn-screen-off"].
  final List<String> scrcpyArgs;

  static Directory configDir() {
    final appData = Platform.environment['APPDATA'];
    final base = appData ?? Platform.environment['HOME'] ?? '.';
    return Directory('$base${Platform.pathSeparator}scrcpy_gui');
  }

  static File configFile() =>
      File('${configDir().path}${Platform.pathSeparator}config.json');

  static DaemonConfig defaults() => DaemonConfig(
        adbPath: _firstExisting([
              _vendorPath('adb', 'adb.exe'),
            ]) ??
            'adb',
        scrcpyPath: _firstExisting([
              _vendorPath('scrcpy', 'scrcpy.exe'),
            ]) ??
            'scrcpy',
        autoLaunch: true,
        ipcPort: kDefaultIpcPort,
        scrcpyArgs: const [],
      );

  /// Loads the config, writing a default file on first run.
  static Future<DaemonConfig> load() async {
    final file = configFile();
    if (!await file.exists()) {
      final config = defaults();
      await config.save();
      return config;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final base = defaults();
      return DaemonConfig(
        adbPath: (json['adbPath'] as String?) ?? base.adbPath,
        scrcpyPath: (json['scrcpyPath'] as String?) ?? base.scrcpyPath,
        autoLaunch: (json['autoLaunch'] as bool?) ?? base.autoLaunch,
        ipcPort: (json['ipcPort'] as int?) ?? base.ipcPort,
        scrcpyArgs: ((json['scrcpyArgs'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
    } catch (e) {
      stderr.writeln('config.json unreadable ($e), using defaults');
      return defaults();
    }
  }

  Future<void> save() async {
    final dir = configDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await configFile().writeAsString(encoder.convert({
      'adbPath': adbPath,
      'scrcpyPath': scrcpyPath,
      'autoLaunch': autoLaunch,
      'ipcPort': ipcPort,
      'scrcpyArgs': scrcpyArgs,
    }));
  }

  /// Looks for a bundled binary in `vendor/` relative to the repo root,
  /// assuming the daemon runs from `packages/daemon`.
  static String? _vendorPath(String folder, String exe) {
    final sep = Platform.pathSeparator;
    return '..$sep..${sep}vendor$sep$folder$sep$exe';
  }

  static String? _firstExisting(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && File(candidate).existsSync()) {
        return File(candidate).absolute.path;
      }
    }
    return null;
  }
}
