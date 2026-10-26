import 'dart:async';

import 'package:scrcpy_core/scrcpy_core.dart';

import 'known_devices.dart';

/// Everything [candidatesToRetry] needs to decide what's worth a reconnect
/// attempt this tick.
class ReconnectSnapshot {
  const ReconnectSnapshot({
    required this.cached,
    required this.live,
    required this.handoffInFlight,
  });

  /// Devices that have gone wireless before, keyed by USB serial.
  final Map<String, KnownWirelessDevice> cached;

  /// The daemon's current device map (same shape as `bin/daemon.dart`'s `known`).
  final Map<String, AdbDevice> live;

  /// USB serials with a `goWireless`/`handoff` currently in flight — those
  /// are already retrying this exact address themselves.
  final Set<String> handoffInFlight;
}

/// What a manual retry ([WirelessReconnector.retryNow]) did.
enum ManualRetryOutcome {
  /// `adb connect` answered "connected to ..."; `trackDevices()` confirms the
  /// device is ready and drives everything after that.
  reconnected,

  /// `adb connect` failed or timed out: nothing answers at the cached address.
  unreachable,

  /// Not tried: the phone is already connected, or a goWireless/handoff for
  /// it is in flight.
  skipped,
}

/// Pure filter: which cached devices deserve a connect attempt this tick.
List<KnownWirelessDevice> candidatesToRetry(ReconnectSnapshot s) {
  return s.cached.values.where((entry) {
    if (s.handoffInFlight.contains(entry.usbSerial)) return false;

    final network = s.live[entry.networkSerial];
    if (network != null && network.isReady) return false;

    final usb = s.live[entry.usbSerial];
    if (usb != null && usb.isReady && !usb.isNetwork) return false;

    return true;
  }).toList();
}

/// Periodically retries `adb connect` for devices that have gone wireless
/// before but aren't currently reachable, so a phone reappears on its own
/// once its network is reachable again — no repeat USB handoff needed.
///
/// This class only fires the connect attempt; `AdbClient.trackDevices()` is
/// what actually confirms readiness and drives auto-launch/IPC broadcasts
/// once a probe succeeds.
class WirelessReconnector {
  WirelessReconnector({
    required this.client,
    this.connectTimeout = const Duration(seconds: 5),
  });

  final AdbClient client;
  final Duration connectTimeout;
  bool _busy = false;

  Timer startPeriodic(
    Duration interval,
    ReconnectSnapshot Function() snapshot, {
    void Function(List<String> reconnectedSerials)? onTick,
  }) {
    return Timer.periodic(interval, (_) async {
      final reconnected = await runOnce(snapshot());
      if (reconnected.isNotEmpty) onTick?.call(reconnected);
    });
  }

  /// Fires connect attempts concurrently for every current candidate,
  /// swallowing per-attempt failures. Skips the tick entirely if a previous
  /// one is still running. Returns network serials whose connect attempt got
  /// a "connected to ..." reply this tick.
  Future<List<String>> runOnce(ReconnectSnapshot snapshot) async {
    if (_busy) return const [];
    _busy = true;
    try {
      final results = await Future.wait(
        candidatesToRetry(snapshot).map(_attempt),
      );
      return [for (final r in results) if (r != null) r];
    } finally {
      _busy = false;
    }
  }

  /// One immediate attempt for [entry], for the UI's "Try Now". Unlike
  /// [runOnce] it is not skipped because a periodic tick happens to be running,
  /// and it reports why nothing was tried, so the caller can tell the user.
  Future<ManualRetryOutcome> retryNow(
    KnownWirelessDevice entry,
    ReconnectSnapshot snapshot,
  ) async {
    final onlyThis = ReconnectSnapshot(
      cached: {entry.usbSerial: entry},
      live: snapshot.live,
      handoffInFlight: snapshot.handoffInFlight,
    );
    if (candidatesToRetry(onlyThis).isEmpty) return ManualRetryOutcome.skipped;
    final connected = await _attempt(entry);
    return connected != null
        ? ManualRetryOutcome.reconnected
        : ManualRetryOutcome.unreachable;
  }

  Future<String?> _attempt(KnownWirelessDevice entry) async {
    try {
      final message = await client
          .connectDevice(entry.lastIp, entry.lastPort)
          .timeout(connectTimeout);
      return AdbClient.connectSucceeded(message) ? entry.networkSerial : null;
    } catch (_) {
      return null;
    }
  }
}
