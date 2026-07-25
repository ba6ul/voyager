import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';

import 'scrcpy_launcher.dart';
import 'wireless.dart';

/// Orchestrates the handoff from USB to wireless for a single device.
///
/// Returns the wireless serial (e.g. '192.168.43.1:5555') on success,
/// or null on failure. On failure, the USB window is left running as a
/// fallback if it's still up.
///
/// [onStatus], if given, is called at each stage transition (see
/// `IpcEvents.handoffStatus` in packages/ipc for the stage names) so a
/// caller can relay progress to a UI without scraping stdout.
Future<String?> handoff({
  required AdbClient client,
  required ScrcpyLauncher launcher,
  required String usbSerial,
  required String deviceName,
  Duration timeout = const Duration(seconds: 30),
  void Function(String stage, [String? detail])? onStatus,
}) async {
  stdout.writeln('[h] initiating handoff for $deviceName ($usbSerial)...');

  // Step 1: Get the phone's WiFi IP (fallback for same-WiFi mode).
  onStatus?.call('readingWifiIp');
  String? phoneWifiIp;
  try {
    phoneWifiIp = await client.wifiIp(usbSerial).timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
    if (phoneWifiIp != null) {
      stdout.writeln('[h] cached WiFi IP: $phoneWifiIp');
    }
  } catch (e) {
    stdout.writeln('[h] could not read WiFi IP: $e');
  }

  // Step 2: Switch phone to TCP mode.
  try {
    stdout.writeln('[h] switching to TCP mode...');
    await client.tcpip(usbSerial).timeout(const Duration(seconds: 5));
    onStatus?.call('tcpipEnabled');
  } catch (e) {
    stdout.writeln('[h] tcpip failed: $e');
    onStatus?.call('failed', 'tcpip failed: $e');
    return null;
  }

  // Step 3: Orchestrate the wireless connection (uses WirelessManager logic).
  onStatus?.call('connecting');
  final wirelessSerial = await _connectWireless(
    client: client,
    phoneWifiIp: phoneWifiIp,
    timeout: timeout,
  );

  if (wirelessSerial == null) {
    // The tcpip restart can drop the USB transport out from under the
    // window that's mirroring it, so it may already be dead by now.
    final usbStillUp = launcher.isRunning(usbSerial);
    stdout.writeln(usbStillUp
        ? '[h] wireless connection failed; USB mirror still running'
        : '[h] wireless connection failed; USB mirror had already stopped');
    onStatus?.call('failed', 'could not reach the device over WiFi');
    return null;
  }

  // Step 4: Open new wireless window.
  stdout.writeln('[h] launching wireless mirror...');
  onStatus?.call('launchingWireless');
  final wirelessLaunched = await launcher.launch(
    wirelessSerial,
    windowTitle: '$deviceName (wireless)',
  );
  if (!wirelessLaunched) {
    stdout.writeln('[h] wireless launch failed');
    onStatus?.call('failed', 'scrcpy failed to launch on $wirelessSerial');
    return null;
  }

  // Step 5: Wait a moment for the new window to fully render.
  await Future<void>.delayed(const Duration(seconds: 1));

  // Step 6: Close the USB window.
  stdout.writeln('[h] closing USB mirror...');
  onStatus?.call('closingUsb');
  launcher.stop(usbSerial);

  stdout.writeln('[h] handoff complete: $deviceName now on wireless');
  onStatus?.call('complete', wirelessSerial);
  return wirelessSerial;
}

/// Inner loop: try to connect to wireless IPs (same-WiFi first, then hotspot
/// gateways). Shares gateway discovery with [WirelessManager.goWireless].
Future<String?> _connectWireless({
  required AdbClient client,
  required String? phoneWifiIp,
  required Duration timeout,
}) async {
  const devicePort = WirelessManager.devicePort;
  final tried = <String>{};
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    // Try same-WiFi first if we have it.
    if (phoneWifiIp != null && !tried.contains(phoneWifiIp)) {
      tried.add(phoneWifiIp);
      stdout.writeln('[h] trying same-WiFi: $phoneWifiIp:$devicePort');
      if (await _tryConnect(client, phoneWifiIp, devicePort)) {
        return '$phoneWifiIp:$devicePort';
      }
    }

    // Try hotspot gateways.
    final gateways = await WirelessManager.defaultGateways();
    for (final ip in gateways) {
      if (tried.contains(ip)) continue;
      tried.add(ip);
      stdout.writeln('[h] trying hotspot gateway: $ip:$devicePort');
      if (await _tryConnect(client, ip, devicePort)) {
        return '$ip:$devicePort';
      }
    }

    // If we've exhausted all candidates, wait and retry (gateways may change).
    if (tried.isEmpty && phoneWifiIp == null) {
      await Future<void>.delayed(const Duration(seconds: 2));
    } else if (tried.isNotEmpty) {
      await Future<void>.delayed(const Duration(seconds: 2));
      tried.clear(); // Allow retries after a pause.
    }
  }

  return null;
}

Future<bool> _tryConnect(AdbClient client, String ip, int port) async {
  try {
    final message = await client
        .connectDevice(ip, port)
        .timeout(const Duration(seconds: 5));
    if (!AdbClient.connectSucceeded(message)) {
      return false;
    }

    // Verify it's ready.
    for (var i = 0; i < 5; i++) {
      final devices = await client.devices();
      if (devices.any((d) => d.serial == '$ip:$port' && d.isReady)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  } catch (_) {}
  return false;
}
