import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';

/// Supplies the PC's IPv4 default gateways. Injectable so tests never depend
/// on the routing table of the machine they run on.
typedef GatewayProvider = Future<Set<String>> Function();

/// Turns a USB-connected device into a wireless one, covering both cases:
///
/// - Hotspot mode: PC joins the phone's hotspot. The phone is the router,
///   so the phone's IP is simply the PC's default gateway on that interface.
/// - Same WiFi: both on one network. The phone's wlan IP is read over USB
///   before unplugging.
///
/// Neither path needs Android's "wireless debugging" toggle; plain USB
/// debugging plus the classic `tcpip 5555` is enough.
class WirelessManager {
  WirelessManager(this.client, {GatewayProvider? gateways})
      : _gateways = gateways ?? defaultGateways;

  final AdbClient client;
  final GatewayProvider _gateways;

  static const devicePort = 5555;

  /// Runs the whole go-wireless flow for [serial]. Returns the network
  /// serial (`ip:5555`) on success, null on timeout.
  ///
  /// [onStatus], if given, is called at each stage transition (see
  /// `IpcEvents.wirelessStatus` in packages/ipc for the stage names) so a
  /// caller can relay progress to a UI without scraping stdout.
  Future<String?> goWireless(
    String serial, {
    Duration timeout = const Duration(minutes: 3),
    void Function(String stage, [String? detail])? onStatus,
  }) async {
    // Grab the phone's WiFi IP first (works only in same-WiFi mode; null
    // when WiFi is off or the phone will act as the hotspot).
    onStatus?.call('readingWifiIp');
    String? phoneWifiIp;
    try {
      phoneWifiIp = await client.wifiIp(serial);
    } catch (_) {}

    stdout.writeln('[w] switching $serial to TCP mode...');
    await client.tcpip(serial, devicePort);
    onStatus?.call('tcpipEnabled');

    stdout.writeln('''
[w] done. Now either:
[w]   a) turn on the phone's hotspot and connect this PC to it, or
[w]   b) keep phone and PC on the same WiFi
[w] then unplug the USB cable. Trying to connect automatically...''');
    onStatus?.call('waitingForHotspot');

    final tried = <String>{};
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final candidates = <String>{
        ...await _gateways(),
        if (phoneWifiIp != null) phoneWifiIp,
      }..removeAll(tried);

      for (final ip in candidates) {
        tried.add(ip);
        stdout.writeln('[w] trying $ip:$devicePort ...');
        onStatus?.call('connecting', '$ip:$devicePort');
        try {
          final message = await client
              .connectDevice(ip, devicePort)
              .timeout(const Duration(seconds: 5));
          if (AdbClient.connectSucceeded(message)) {
            final networkSerial = '$ip:$devicePort';
            if (await _isReady(networkSerial)) {
              stdout.writeln('[w] connected wirelessly: $networkSerial');
              onStatus?.call('connected', networkSerial);
              return networkSerial;
            }
          }
        } catch (_) {}
      }

      // Gateways change when the PC joins the hotspot, so keep retrying
      // previously failed ones after a while.
      if (candidates.isEmpty && tried.isNotEmpty) {
        await Future<void>.delayed(const Duration(seconds: 6));
        tried.clear();
      } else {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    stdout.writeln('[w] gave up after ${timeout.inMinutes} minutes');
    onStatus?.call('failed', 'timed out after ${timeout.inMinutes} minutes');
    return null;
  }

  Future<bool> _isReady(String networkSerial) async {
    for (var i = 0; i < 5; i++) {
      final devices = await client.devices();
      for (final d in devices) {
        if (d.serial == networkSerial && d.isReady) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// All IPv4 default gateways on this PC, parsed from `route print -4`.
  /// On a phone hotspot, the phone itself is one of these.
  static Future<Set<String>> defaultGateways() async {
    try {
      final result = await Process.run('route', ['print', '-4']);
      if (result.exitCode != 0) return {};
      return parseDefaultGateways(result.stdout as String);
    } catch (_) {
      return {};
    }
  }

  /// Extracts the gateway of every default route (`0.0.0.0 0.0.0.0 <gw> ...`)
  /// from `route print -4` output. Rows whose gateway is not an address, such
  /// as `On-link`, are skipped, and the same gateway on several interfaces is
  /// reported once. Only the numeric rows are matched, so the output language
  /// does not matter.
  static Set<String> parseDefaultGateways(String routePrintOutput) {
    final pattern = RegExp(
      r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d{1,3}(?:\.\d{1,3}){3})',
      multiLine: true,
    );
    return pattern
        .allMatches(routePrintOutput)
        .map((m) => m.group(1)!)
        .toSet();
  }
}
