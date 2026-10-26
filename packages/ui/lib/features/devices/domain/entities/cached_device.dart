import 'package:equatable/equatable.dart';

/// A device that has gone wireless before, remembered by the daemon so it
/// can be reconnected automatically (or on request) without another USB
/// handoff — see `packages/daemon/lib/src/known_devices.dart`.
class CachedDevice extends Equatable {
  const CachedDevice({
    required this.usbSerial,
    required this.model,
    required this.lastIp,
    required this.lastPort,
  });

  /// The USB serial that originally went wireless; stable identity key.
  final String usbSerial;
  final String model;
  final String lastIp;
  final int lastPort;

  String get networkSerial => '$lastIp:$lastPort';

  /// Whether [liveSerial], a serial the daemon lists right now, is this same
  /// phone. adb names one phone differently per transport, so a plain
  /// comparison with [networkSerial] misses two of the three forms:
  /// - `ip:port` (the address it went wireless on),
  /// - its USB serial (`usbSerial` itself), and
  /// - the wireless-debugging form `adb-<usbSerial>-<suffix>._adb-tls-connect._tcp`,
  ///   which embeds the same hardware serial.
  bool isRepresentedBy(String liveSerial) =>
      liveSerial == networkSerial ||
      liveSerial == usbSerial ||
      (liveSerial.startsWith('adb-$usbSerial-') &&
          liveSerial.endsWith('._adb-tls-connect._tcp'));

  @override
  List<Object?> get props => [usbSerial, model, lastIp, lastPort];
}
