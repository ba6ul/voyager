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
  WirelessManager(
    this.client, {
    GatewayProvider? gateways,
    this.tcpipTimeout = const Duration(seconds: 5),
    this.settleTimeout = const Duration(seconds: 15),
    this.settlePollInterval = const Duration(milliseconds: 500),
  }) : _gateways = gateways ?? defaultGateways;

  final AdbClient client;
  final GatewayProvider _gateways;

  /// How long to wait for the phone to acknowledge the switch to TCP mode.
  /// Same as handoff's limit.
  final Duration tcpipTimeout;

  /// How long [settle] waits for a phone to be back and ready.
  final Duration settleTimeout;
  final Duration settlePollInterval;

  /// Serials whose last `tcpip` timed out. A timeout does not prove the phone
  /// did not switch: it may still do so, which restarts adbd and drops the
  /// USB connection for a moment. Until [settle] has seen the phone ready
  /// again, nothing new should be sent to it.
  final Set<String> _uncertain = {};

  static const devicePort = 5555;

  /// Records that the phone's state after a `tcpip` request is unknown (it
  /// timed out and was not followed by a confirmed connection), so the next
  /// operation on it calls [settle] first.
  void markUncertain(String serial) => _uncertain.add(serial);

  /// Makes sure the phone's real state is known before something new is
  /// sent to it. A no-op (true) unless an earlier `tcpip` for [serial] timed
  /// out; then it waits for the phone to show up as ready in adb and stay
  /// ready across two checks (so an adbd restart that is still under way does
  /// not count), and returns false if that does not happen in time.
  ///
  /// The wait is reported through [onStatus] as `waitingForPhone` (and in the
  /// daemon log) so it is not silent; the caller reports the failure if this
  /// returns false.
  Future<bool> settle(
    String serial, {
    void Function(String stage, [String? detail])? onStatus,
  }) async {
    if (!_uncertain.contains(serial)) return true;
    stdout.writeln('[w] waiting up to ${settleTimeout.inSeconds} s for $serial '
        'to be ready again after an unanswered request');
    onStatus?.call(
        'waitingForPhone',
        'the phone did not answer the last request; waiting up to '
            '${settleTimeout.inSeconds} s for it to be ready');
    final deadline = DateTime.now().add(settleTimeout);
    var readyChecks = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final devices = await client.devices();
        final ready = devices.any((d) => d.serial == serial && d.isReady);
        readyChecks = ready ? readyChecks + 1 : 0;
        if (readyChecks >= 2) {
          _uncertain.remove(serial);
          return true;
        }
      } catch (_) {
        readyChecks = 0;
      }
      await Future<void>.delayed(settlePollInterval);
    }
    return false;
  }

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
    // An earlier attempt may have timed out without the phone having
    // answered; do not send it anything new until it is back and ready.
    if (!await settle(serial, onStatus: onStatus)) {
      stdout.writeln('[w] $serial has not settled after the previous attempt');
      onStatus?.call(
          'failed',
          'the phone has not come back since the last attempt to switch it to '
              'TCP mode; wait for it to reconnect and try again');
      return null;
    }

    // Grab the phone's WiFi IP first (works only in same-WiFi mode; null
    // when WiFi is off or the phone will act as the hotspot).
    onStatus?.call('readingWifiIp');
    String? phoneWifiIp;
    try {
      phoneWifiIp = await client.wifiIp(serial).timeout(tcpipTimeout);
    } catch (_) {}

    stdout.writeln('[w] switching $serial to TCP mode...');
    final request = client.tcpip(serial, devicePort);
    try {
      await request.timeout(tcpipTimeout);
    } on TimeoutException {
      // No answer is not proof it failed: the phone may still switch (and
      // restart adbd) a moment later. Report a failure, leave the USB mirror
      // alone, and remember the serial so the next operation on it checks the
      // phone's real state first.
      _uncertain.add(serial);
      stdout.writeln('[w] tcpip for $serial did not answer within '
          '${tcpipTimeout.inSeconds} s');
      unawaited(request.then(
        (_) => stdout.writeln('[w] tcpip for $serial completed late'),
        onError: (Object e) =>
            stdout.writeln('[w] tcpip for $serial failed late: $e'),
      ));
      onStatus?.call(
          'failed',
          'the phone did not answer the switch to TCP mode within '
              '${tcpipTimeout.inSeconds} s. It may still switch; wait for it '
              'to reconnect, then try again. The USB mirror was left as it is.');
      return null;
    } catch (e) {
      // Unknown or just-unplugged serial (AdbServerException), adb server
      // gone (SocketException), ...: report it instead of throwing past the
      // caller, which is a fire-and-forget task.
      stdout.writeln('[w] tcpip failed: $e');
      onStatus?.call('failed', 'tcpip failed: $e');
      return null;
    }
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
