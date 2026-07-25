/// Connection state as reported by the adb server.
enum AdbDeviceState {
  /// Ready for commands.
  device,

  /// Connected but the user has not accepted the RSA prompt on the phone.
  unauthorized,

  /// Visible but not responding (common right after `adb connect`).
  offline,

  /// Device is in recovery mode.
  recovery,

  /// Device is in bootloader/fastboot mode.
  bootloader,

  /// Anything adb reports that we do not model explicitly.
  unknown;

  static AdbDeviceState parse(String raw) {
    switch (raw.trim()) {
      case 'device':
        return AdbDeviceState.device;
      case 'unauthorized':
        return AdbDeviceState.unauthorized;
      case 'offline':
        return AdbDeviceState.offline;
      case 'recovery':
        return AdbDeviceState.recovery;
      case 'bootloader':
        return AdbDeviceState.bootloader;
      default:
        return AdbDeviceState.unknown;
    }
  }
}

/// A device entry as listed by `host:devices` or `host:track-devices`.
class AdbDevice {
  const AdbDevice({required this.serial, required this.state});

  /// USB serial (e.g. `R58M12ABCDE`) or network address (e.g. `192.168.43.1:5555`).
  final String serial;

  final AdbDeviceState state;

  /// True when this entry came from `adb connect` rather than USB.
  bool get isNetwork => serial.contains(':');

  bool get isReady => state == AdbDeviceState.device;

  @override
  bool operator ==(Object other) =>
      other is AdbDevice && other.serial == serial && other.state == state;

  @override
  int get hashCode => Object.hash(serial, state);

  @override
  String toString() => 'AdbDevice($serial, ${state.name})';
}
