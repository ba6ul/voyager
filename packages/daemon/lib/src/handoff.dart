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
  Duration tcpipTimeout = const Duration(seconds: 5),
  GatewayProvider? gateways,
  void Function(String stage, [String? detail])? onStatus,

  /// Called when the `tcpip` request went unanswered and the handoff then
  /// ended without a confirmed wireless connection: the phone may still
  /// switch to TCP mode later, so its state is unknown. The caller should
  /// settle the phone before sending it anything else.
  void Function()? onTcpipUnconfirmed,
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
  var tcpipUnanswered = false;
  try {
    stdout.writeln('[h] switching to TCP mode...');
    await client.tcpip(usbSerial).timeout(tcpipTimeout);
    onStatus?.call('tcpipEnabled');
  } on TimeoutException {
    // adb serializes access to a device's transport, so this can time out
    // for a real, caused reason rather than a lost ack: if scrcpy's own
    // process was still mid-connection on this same transport when handoff
    // started (launching does not mean connected - see ScrcpyLauncher docs),
    // our separate tcpip request has to wait behind it. The phone very
    // likely did switch to TCP mode regardless, so proceed to the connect
    // step instead of aborting; a genuine tcpip failure (bad serial, adb
    // rejecting the request) throws AdbServerException, not this.
    stdout.writeln('[h] tcpip ack delayed, proceeding anyway (device likely switched)');
    // Not "tcpipEnabled": nothing confirmed it. Say what is known.
    tcpipUnanswered = true;
    onStatus?.call('tcpipUnconfirmed',
        'the phone did not acknowledge the switch to TCP mode; trying to '
            'connect anyway');
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
    gateways: gateways ?? WirelessManager.defaultGateways,
  );

  if (wirelessSerial == null) {
    // Nothing answered at the phone's wireless addresses. If its tcpip request
    // also went unanswered, the phone may still switch later (restarting adbd
    // and dropping USB), so let the caller reconcile before the next request.
    if (tcpipUnanswered) onTcpipUnconfirmed?.call();
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
  final LaunchResult launchResult;
  try {
    launchResult = await launcher.launch(
      wirelessSerial,
      windowTitle: '$deviceName (wireless)',
    );
  } catch (e) {
    // e.g. ProcessException when scrcpyPath does not exist. The USB mirror is
    // untouched at this point, so it keeps running as the fallback.
    stdout.writeln('[h] wireless launch failed: $e');
    onStatus?.call('failed', 'scrcpy failed to launch on $wirelessSerial: $e');
    return null;
  }
  if (launchResult == LaunchResult.alreadyRunning) {
    // e.g. auto-launch already opened a mirror on this address. That is the
    // result handoff wants, so carry on and close the USB mirror.
    stdout.writeln('[h] wireless mirror was already running');
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
  required GatewayProvider gateways,
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
    final candidates = await gateways();
    for (final ip in candidates) {
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
