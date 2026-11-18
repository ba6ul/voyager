import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';

/// Where a pairing got to. Sent to the UI as the `stage` of a `pairingStatus`.
abstract final class PairingStages {
  static const pairing = 'pairing';
  static const searching = 'searching';

  /// Paired and connected; `detail` is the connected serial.
  static const connected = 'connected';

  /// Paired, but the phone's connect port was not found.
  static const pairedOnly = 'pairedOnly';
  static const wrongCode = 'wrongCode';
  static const unreachable = 'unreachable';
  static const failed = 'failed';
}

/// Open TCP ports on [host] between [from] and [to], excluding [skip].
typedef PortScanner = Future<List<int>> Function(
    String host, int from, int to, Set<int> skip);

/// Pairs a phone for Wireless debugging and then connects to it, so the user
/// types only what the phone's pairing dialog shows.
///
/// Pairing (`host:pair`) needs the 6-digit code and the pairing address. The
/// connection afterwards uses a different, random port that adb normally
/// learns through mDNS. If adb does not connect by itself (mDNS blocked on
/// this PC), the pairing host is scanned for open ports and each is offered
/// to `adb connect`.
class WirelessDebuggingPairer {
  WirelessDebuggingPairer({
    required this.client,
    PortScanner? scanPorts,
    this.autoConnectWait = const Duration(seconds: 4),
    this.pollInterval = const Duration(milliseconds: 500),
    this.scanWindow = const Duration(seconds: 20),
    this.scanRetryInterval = const Duration(seconds: 1),
    this.readyWait = const Duration(seconds: 4),
    this.scanFrom = 32768,
    this.scanTo = 60999,
  }) : _scan = scanPorts ?? scanOpenPorts;

  final AdbClient client;
  final PortScanner _scan;

  /// How long adb gets to connect on its own after pairing.
  final Duration autoConnectWait;
  final Duration pollInterval;

  /// How long to keep scanning: right after pairing the phone's ports are
  /// still changing, so one scan can miss the real connect port.
  final Duration scanWindow;
  final Duration scanRetryInterval;

  /// How long a connected port gets to reach the `device` state.
  final Duration readyWait;

  /// Linux's ephemeral range, where Android picks the Wireless debugging port.
  final int scanFrom;
  final int scanTo;

  bool _busy = false;

  /// Whether a pairing is running; only one at a time.
  bool get busy => _busy;

  /// Runs the whole flow and reports each stage through [onStatus]. Never
  /// throws for an expected failure. [address] and [code] must already be
  /// valid (see [AdbPairing]); the code is never reported.
  Future<void> pair(
    String address,
    String code, {
    required void Function(String stage, [String? detail]) onStatus,
    void Function(String identity, String networkSerial)? onConnected,
  }) async {
    if (_busy) {
      onStatus(PairingStages.failed, 'a pairing is already in progress');
      return;
    }
    _busy = true;
    try {
      onStatus(PairingStages.pairing);
      final PairResult result;
      try {
        result = await client.pair(address, code);
      } catch (e) {
        onStatus(PairingStages.failed, 'could not pair: $e');
        return;
      }
      switch (result.outcome) {
        case PairOutcome.wrongCode:
          onStatus(PairingStages.wrongCode, result.message);
          return;
        case PairOutcome.unreachable:
          onStatus(PairingStages.unreachable, result.message);
          return;
        case PairOutcome.failed:
          onStatus(PairingStages.failed, result.message);
          return;
        case PairOutcome.paired:
          break;
      }

      onStatus(PairingStages.searching);
      final host = address.substring(0, address.lastIndexOf(':'));
      final pairingPort = int.parse(address.substring(address.lastIndexOf(':') + 1));
      final serial = await _awaitAutoConnect(result.guid) ??
          await _connectByScanning(host, pairingPort);
      if (serial == null) {
        onStatus(PairingStages.pairedOnly,
            'paired, but the phone\'s connect address was not found');
        return;
      }
      final identity = result.guid == null
          ? null
          : AdbTransport.hardwareSerialOf('${result.guid}._adb-tls-connect._tcp');
      if (identity != null) onConnected?.call(identity, serial);
      onStatus(PairingStages.connected, serial);
    } catch (e) {
      onStatus(PairingStages.failed, '$e');
    } finally {
      _busy = false;
    }
  }

  /// adb may connect to a freshly paired phone itself (through mDNS). Waits
  /// briefly for that, returning the serial it appeared under.
  Future<String?> _awaitAutoConnect(String? guid) async {
    if (guid == null) return null;
    final serial = '$guid._adb-tls-connect._tcp';
    final deadline = DateTime.now().add(autoConnectWait);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final devices = await client.devices();
        if (devices.any((d) => d.serial == serial && d.isReady)) return serial;
      } catch (_) {}
      await Future<void>.delayed(pollInterval);
    }
    return null;
  }

  /// Scans the host for open ports and offers each to `adb connect` until one
  /// becomes a ready device, retrying for [scanWindow]. A phone listens on
  /// several ports and only one is adb's, so a port that says "connected" but
  /// stays offline is disconnected again instead of being left behind.
  Future<String?> _connectByScanning(String host, int pairingPort) async {
    final deadline = DateTime.now().add(scanWindow);
    do {
      final ports = await _scan(host, scanFrom, scanTo, {pairingPort});
      for (final port in ports) {
        final serial = '$host:$port';
        try {
          final message = await client
              .connectDevice(host, port)
              .timeout(const Duration(seconds: 5));
          if (!AdbClient.connectSucceeded(message)) continue;
          if (await _awaitReady(serial)) return serial;
          await client.disconnectDevice(host, port);
        } catch (_) {}
      }
      await Future<void>.delayed(scanRetryInterval);
    } while (DateTime.now().isBefore(deadline));
    return null;
  }

  Future<bool> _awaitReady(String serial) async {
    final deadline = DateTime.now().add(readyWait);
    do {
      try {
        final devices = await client.devices();
        if (devices.any((d) => d.serial == serial && d.isReady)) return true;
      } catch (_) {}
      await Future<void>.delayed(pollInterval);
    } while (DateTime.now().isBefore(deadline));
    return false;
  }
}

/// Real [PortScanner]: tries each port with a short timeout, a few hundred at
/// a time. A phone on the LAN refuses closed ports at once, so a full range
/// takes a few seconds.
Future<List<int>> scanOpenPorts(
  String host,
  int from,
  int to,
  Set<int> skip, {
  Duration timeout = const Duration(milliseconds: 400),
  int concurrency = 400,
}) async {
  final open = <int>[];
  var next = from;

  Future<void> worker() async {
    while (true) {
      final port = next++;
      if (port > to) return;
      if (skip.contains(port)) continue;
      try {
        final socket = await Socket.connect(host, port, timeout: timeout);
        socket.destroy();
        open.add(port);
      } catch (_) {}
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  open.sort();
  return open;
}
