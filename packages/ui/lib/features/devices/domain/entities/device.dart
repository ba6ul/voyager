import 'package:equatable/equatable.dart';

/// Connection state as reported by the daemon (mirrors `AdbDeviceState` on
/// the wire, without depending on scrcpy_core directly).
enum DeviceState {
  device,
  unauthorized,
  offline,
  recovery,
  bootloader,
  unknown;

  static DeviceState parse(String raw) => DeviceState.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => DeviceState.unknown,
      );
}

/// A device as known to the daemon: USB serial (e.g. `R58M12ABCDE`) or
/// network address (e.g. `192.168.43.1:5555`).
class Device extends Equatable {
  const Device({
    required this.serial,
    required this.state,
    required this.mirroring,
    this.model,
  });

  final String serial;
  final DeviceState state;
  final String? model;

  /// Whether the daemon currently has a scrcpy window open for this serial.
  final bool mirroring;

  bool get isNetwork => serial.contains(':');
  bool get isReady => state == DeviceState.device;

  @override
  List<Object?> get props => [serial, state, model, mirroring];
}
