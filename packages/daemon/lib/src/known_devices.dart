import 'dart:convert';
import 'dart:io';

import 'config.dart';

/// A device that has successfully gone wireless before (via `goWireless` or
/// `handoff`), remembered so the daemon can try reconnecting to it on its own
/// the next time it's reachable, without another USB handoff.
class KnownWirelessDevice {
  const KnownWirelessDevice({
    required this.usbSerial,
    required this.model,
    required this.lastIp,
    required this.lastPort,
  });

  /// The USB serial that originally went wireless. Stable identity key,
  /// unlike the wireless `ip:port`, which can change between sessions.
  final String usbSerial;

  /// Cached at write time so a reconnect attempt never needs to reach the
  /// device (which may not be present at all) just to know its name.
  final String model;

  final String lastIp;
  final int lastPort;

  String get networkSerial => '$lastIp:$lastPort';

  factory KnownWirelessDevice.fromJson(Map<String, dynamic> json) =>
      KnownWirelessDevice(
        usbSerial: json['usbSerial'] as String,
        model: json['model'] as String,
        lastIp: json['lastIp'] as String,
        lastPort: json['lastPort'] as int,
      );

  Map<String, dynamic> toJson() => {
        'usbSerial': usbSerial,
        'model': model,
        'lastIp': lastIp,
        'lastPort': lastPort,
      };
}

/// Loads/saves the set of [KnownWirelessDevice]s at
/// `%APPDATA%\scrcpy_gui\known_wireless_devices.json`, alongside but separate
/// from `config.json` — this is daemon-managed runtime state, not a user
/// setting, so it isn't part of `DaemonConfig`'s daemon/UI settings contract.
abstract final class KnownDevicesStore {
  static File _file({File? file}) =>
      file ??
      File('${DaemonConfig.configDir().path}${Platform.pathSeparator}'
          'known_wireless_devices.json');

  /// Returns an empty map if the file doesn't exist yet (nothing has gone
  /// wireless this install) or can't be parsed.
  static Future<Map<String, KnownWirelessDevice>> load({File? file}) async {
    final target = _file(file: file);
    if (!await target.exists()) return {};
    try {
      final json = jsonDecode(await target.readAsString()) as Map<String, dynamic>;
      final entries = (json['devices'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(KnownWirelessDevice.fromJson);
      return {for (final e in entries) e.usbSerial: e};
    } catch (e) {
      stderr.writeln('known_wireless_devices.json unreadable ($e), ignoring');
      return {};
    }
  }

  static Future<void> save(
    Map<String, KnownWirelessDevice> devices, {
    File? file,
  }) async {
    final target = _file(file: file);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await target.writeAsString(encoder.convert({
      'devices': devices.values.map((d) => d.toJson()).toList(),
    }));
  }
}
