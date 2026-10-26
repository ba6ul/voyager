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

  @override
  List<Object?> get props => [usbSerial, model, lastIp, lastPort];
}
