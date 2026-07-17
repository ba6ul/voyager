import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/config.dart';
import 'package:scrcpy_daemon/src/scrcpy_launcher.dart';
import 'package:scrcpy_daemon/src/wireless.dart';

/// Main execution engine and event coordinator for the scrcpy background daemon.
///
/// This application bootstraps local resource configurations, mounts low-level 
/// hardware monitoring streams via an active `AdbClient`, and registers unified 
/// terminal feedback loops to handle explicit runtime operations.
///
/// Concurrent Lifecycle Pipelines:
/// 1. Hardware State Tracking: Observes hardware topology shifts via infinite ADB socket subscriptions, executing state diffing and auto-launch policies.
/// 2. Interactive Terminal I/O: Exposes localized shell evaluation protocols to command manual network routing topology changes.
/// 3. Resource Destruction: Binds platform signal listeners to ensure complete sub-process evacuation during abrupt termination.
Future<void> main(List<String> args) async {
  final config = await DaemonConfig.load();
  final adbPath = args.isNotEmpty ? args.first : config.adbPath;

  final client = AdbClient(adbPath: adbPath);
  final launcher = ScrcpyLauncher(
    scrcpyPath: config.scrcpyPath,
    baseArgs: config.scrcpyArgs,
  );
  final wireless = WirelessManager(client);

  stdout.writeln('config: ${DaemonConfig.configFile().path}');
  stdout.writeln('adb: $adbPath | scrcpy: ${config.scrcpyPath} | '
      'autoLaunch: ${config.autoLaunch}');
  stdout.writeln('starting adb server if needed...');
  await client.ensureServerRunning();
  stdout.writeln('adb server protocol version: ${await client.serverVersion()}');
  stdout.writeln(
      'watching for devices | commands: w=wireless u=usb l=list q=quit\n');

  var known = <String, AdbDevice>{};

  ProcessSignal.sigint.watch().listen((_) {
    launcher.stopAll();
    exit(0);
  });

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) async {
    final command = line.trim().toLowerCase();
    switch (command) {
      case 'w':
        final usb = known.values
            .where((d) => d.isReady && !d.isNetwork)
            .toList();
        if (usb.isEmpty) {
          stdout.writeln('[w] no USB device connected; plug in first');
          return;
        }
        unawaited(wireless.goWireless(usb.first.serial));
        // On success the network device appears in track-devices and
        // autoLaunch opens the mirror by itself.
        break;
      case 'u':
        for (final d in known.values.where((d) => d.isReady)) {
          if (d.isNetwork) {
            final parts = d.serial.split(':');
            await client.disconnectDevice(parts[0], int.parse(parts[1]));
            stdout.writeln('[u] disconnected ${d.serial}');
          } else {
            await client.usbMode(d.serial);
            stdout.writeln('[u] ${d.serial} back to USB-only (port closed)');
          }
        }
        break;
      case 'l':
        if (known.isEmpty) stdout.writeln('(no devices)');
        for (final d in known.values) {
          stdout.writeln('  ${d.serial}  ${d.state.name}'
              '${d.isNetwork ? "  (wireless)" : ""}');
        }
        break;
      case 'q':
        launcher.stopAll();
        exit(0);
      default:
        if (command.isNotEmpty) {
          stdout.writeln('commands: w=wireless u=usb l=list q=quit');
        }
    }
  });

  while (true) {
    try {
      await for (final snapshot in client.trackDevices()) {
        final current = {for (final d in snapshot) d.serial: d};

        for (final device in current.values) {
          final previous = known[device.serial];
          final becameReady =
              device.isReady && (previous == null || !previous.isReady);
          if (previous == null) {
            _logAttached(device);
          } else if (previous.state != device.state) {
            stdout.writeln('[~] ${device.serial}: '
                '${previous.state.name} -> ${device.state.name}');
          }
          if (becameReady) {
            known = {...known, device.serial: device};
            await _onReady(client, launcher, config, device);
          }
        }
        for (final serial in known.keys) {
          if (!current.containsKey(serial)) {
            stdout.writeln('[-] $serial disconnected');
          }
        }
        known = current;
      }
      stdout.writeln('track-devices stream closed, reconnecting...');
    } catch (e) {
      stdout.writeln('adb server unreachable ($e), retrying in 2s...');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await client.ensureServerRunning();
  }
}

void _logAttached(AdbDevice device) {
  if (device.state == AdbDeviceState.unauthorized) {
    stdout.writeln('[!] ${device.serial} connected but unauthorized: '
        'accept the prompt on the phone');
  } else if (!device.isReady) {
    stdout.writeln(
        '[?] ${device.serial} attached in state ${device.state.name}');
  }
}

Future<void> _onReady(
  AdbClient client,
  ScrcpyLauncher launcher,
  DaemonConfig config,
  AdbDevice device,
) async {
  final name = await client.model(device.serial);
  final kind = device.isNetwork ? 'wireless' : 'USB';
  stdout.writeln('[+] $name (${device.serial}) connected via $kind');

  if (!config.autoLaunch) return;
  final launched = await launcher.launch(device.serial, windowTitle: name);
  stdout.writeln(launched
      ? '[>] scrcpy launched for $name'
      : '[=] scrcpy already running for $name');
}
