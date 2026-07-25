import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/scrcpy_launcher.dart';
import 'package:test/test.dart';

/// Import the FakeAdbServer from core tests. You'll need to move it to a
/// shared location (e.g., packages/core/lib/src/test_helpers/) if it's not
/// importable from here. For now, this assumes you've exposed it.
///
/// TODO: move FakeAdbServer to packages/core/lib/src/testing/fake_server.dart
/// and export it from scrcpy_core.dart so daemon/test can import it.
// import 'package:scrcpy_core/src/testing/fake_server.dart';

/// Mock launcher that records all launch() and stop() calls for verification.
class MockScrcpyLauncher implements ScrcpyLauncher {
  @override
  final String scrcpyPath = 'mock-scrcpy';

  @override
  final List<String> baseArgs = const [];
  final List<LaunchCall> launches = [];
  final List<String> stops = [];
  final Map<String, bool> _running = {};

  @override
  Future<bool> launch(
    String serial, {
    String? windowTitle,
    List<String> extraArgs = const [],
  }) async {
    launches.add(LaunchCall(serial, windowTitle, extraArgs));
    _running[serial] = true;
    return true;
  }

  @override
  void stop(String serial) {
    stops.add(serial);
    _running.remove(serial);
  }

  @override
  void stopAll() {
    _running.clear();
  }

  @override
  bool isRunning(String serial) => _running[serial] ?? false;

  /// Helper: get the order of launches and stops as a readable trace.
  List<String> getEventTrace() {
    final events = <String>[];
    var launchIdx = 0;
    var stopIdx = 0;
    while (launchIdx < launches.length || stopIdx < stops.length) {
      if (launchIdx < launches.length &&
          (stopIdx >= stops.length ||
              launches[launchIdx].serial.compareTo(stops[stopIdx]) <= 0)) {
        final call = launches[launchIdx];
        events.add('launch(${call.serial})');
        launchIdx++;
      } else {
        events.add('stop(${stops[stopIdx]})');
        stopIdx++;
      }
    }
    return events;
  }
}

class LaunchCall {
  LaunchCall(this.serial, this.windowTitle, this.extraArgs);
  final String serial;
  final String? windowTitle;
  final List<String> extraArgs;
}

void main() {
  group('Handoff (USB -> Wireless)', () {
    late MockScrcpyLauncher launcher;
    late AdbClient client;

    setUp(() {
      launcher = MockScrcpyLauncher();
      // TODO: Once FakeAdbServer is importable, set it up here.
      // For now, this test is a skeleton showing the structure.
    });

    test('handoff opens wireless window before closing USB window', () {
      // TODO: Implement using FakeAdbServer
      // 1. Start fake server on loopback
      // 2. Create AdbClient pointing to fake server port
      // 3. Emit USB device ready: FakeAdbServer.pushTrackSnapshot('FAKESERIAL\tdevice\n')
      // 4. Call handoff logic (see handoff_impl below)
      // 5. Emit wireless device ready: FakeAdbServer.pushTrackSnapshot('FAKESERIAL\tdevice\n192.168.43.1:5555\tdevice\n')
      // 6. Assert launcher.launches has two entries in order: USB then wireless
      // 7. Assert launcher.stops has one entry: USB serial
      // 8. Assert event trace is: launch(FAKESERIAL), launch(192.168.43.1:5555), stop(FAKESERIAL)
      // Skip this test for now
    },
        skip:
            'FakeAdbServer not yet importable; move it to core/lib/src/testing/');

    test('handoff times out if wireless never appears', () {
      // TODO: Simulate tcpip succeeding, but adb connect times out
      // Assert: USB window stays open, error is logged, wireless window never opened
    }, skip: 'FakeAdbServer not yet importable');
    test('handoff reverts if new window fails to launch', () {
      // TODO: Mock launcher to fail on wireless launch
      // Assert: USB window stays open, error logged, wireless process killed
    }, skip: 'FakeAdbServer not yet importable');
  });
}

// ============================================================================
// HANDOFF IMPLEMENTATION (placeholder: copy this into packages/daemon/lib/src/handoff.dart)
// ============================================================================

/// Orchestrates the handoff from USB to wireless for a single device.
///
/// Returns the wireless serial (e.g. '192.168.43.1:5555') on success,
/// or null on failure. On failure, the USB window is left running as a fallback.
Future<String?> handoff({
  required AdbClient client,
  required ScrcpyLauncher launcher,
  required String usbSerial,
  required String deviceName,
  Duration timeout = const Duration(seconds: 30),
}) async {
  stdout.writeln('[h] initiating handoff for $deviceName ($usbSerial)...');

  // Step 1: Get the phone's WiFi IP (fallback for same-WiFi mode).
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
  } catch (e) {
    stdout.writeln('[h] tcpip failed: $e');
    return null;
  }

  // Step 3: Orchestrate the wireless connection (uses WirelessManager logic).
  final wirelessSerial = await _connectWireless(
    client: client,
    phoneWifiIp: phoneWifiIp,
    timeout: timeout,
  );

  if (wirelessSerial == null) {
    stdout.writeln('[h] wireless connection failed; USB mirror still running');
    return null;
  }

  // Step 4: Open new wireless window.
  stdout.writeln('[h] launching wireless mirror...');
  final wirelessLaunched = await launcher.launch(
    wirelessSerial,
    windowTitle: '$deviceName (wireless)',
  );
  if (!wirelessLaunched) {
    stdout.writeln('[h] wireless launch failed');
    return null;
  }

  // Step 5: Wait a moment for the new window to fully render.
  await Future<void>.delayed(const Duration(seconds: 1));

  // Step 6: Close the USB window.
  stdout.writeln('[h] closing USB mirror...');
  launcher.stop(usbSerial);

  stdout.writeln('[h] handoff complete: $deviceName now on wireless');
  return wirelessSerial;
}

/// Inner loop: try to connect to wireless IPs (same-WiFi first, then hotspot gateways).
/// This is extracted from WirelessManager.goWireless() for reuse.
Future<String?> _connectWireless({
  required AdbClient client,
  required String? phoneWifiIp,
  required Duration timeout,
}) async {
  const devicePort = 5555;
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
    final gateways = await _getDefaultGateways();
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

Future<Set<String>> _getDefaultGateways() async {
  try {
    final result = await Process.run('route', ['print', '-4']);
    if (result.exitCode != 0) return {};
    final pattern = RegExp(
      r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d{1,3}(?:\.\d{1,3}){3})',
      multiLine: true,
    );
    return pattern
        .allMatches(result.stdout as String)
        .map((m) => m.group(1)!)
        .toSet();
  } catch (_) {
    return {};
  }
}
