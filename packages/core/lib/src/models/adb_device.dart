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

/// How adb reaches a device, told apart from its serial alone.
///
/// adb names one phone differently per route, and the name decides what can be
/// done with it: only a phone on [usb] can be switched to TCP mode, so Go
/// Wireless and handoff are offered for nothing else.
///
/// Serial shapes (all seen from real adb; the mDNS and emulator ones on
/// 2026-10-28):
/// - [usb]: the bare hardware serial, e.g. `65261XEA33U4D0`.
/// - [network]: an address added with `adb connect`, e.g. `192.168.43.1:5555`
///   or `[fe80::1]:5555`.
/// - [mdns]: wireless debugging, e.g.
///   `adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp`. It has no colon, so
///   the old "contains ':'" rule called it USB.
/// - [emulator]: e.g. `emulator-5554`. Also no colon, also called USB before.
enum AdbTransport {
  usb,
  network,
  mdns,
  emulator;

  static const _mdnsPrefix = 'adb-';
  static const _mdnsSuffix = '._adb-tls-connect._tcp';
  static final _emulator = RegExp(r'^emulator-\d+$');

  /// Classifies [serial]. Anything that is not recognisably one of the other
  /// three is [usb], which is what adb lists a plain hardware serial as.
  static AdbTransport of(String serial) {
    if (_emulator.hasMatch(serial)) return emulator;
    if (_isMdns(serial)) return mdns;
    if (serial.contains(':')) return network;
    return usb;
  }

  static bool _isMdns(String serial) =>
      serial.startsWith(_mdnsPrefix) &&
      serial.endsWith(_mdnsSuffix) &&
      _mdnsHardwareSerial(serial) != null;

  /// The hardware serial inside a wireless-debugging name
  /// (`adb-<serial>-<suffix>._adb-tls-connect._tcp`), or null if [serial] is
  /// not of that shape.
  static String? _mdnsHardwareSerial(String serial) {
    if (!serial.startsWith(_mdnsPrefix) || !serial.endsWith(_mdnsSuffix)) {
      return null;
    }
    final middle = serial.substring(
        _mdnsPrefix.length, serial.length - _mdnsSuffix.length);
    final dash = middle.lastIndexOf('-');
    if (dash <= 0 || dash == middle.length - 1) return null;
    return middle.substring(0, dash);
  }

  /// The phone's hardware serial when the serial itself carries it: the serial
  /// for [usb], the embedded part for [mdns]. Null for [network] and
  /// [emulator], whose serials say nothing about which device it is (an
  /// emulator's `ro.serialno` differs from its adb serial).
  static String? hardwareSerialOf(String serial) {
    switch (of(serial)) {
      case usb:
        return serial;
      case mdns:
        return _mdnsHardwareSerial(serial);
      case network:
      case emulator:
        return null;
    }
  }
}

/// A device entry as listed by `host:devices` or `host:track-devices`.
class AdbDevice {
  const AdbDevice({required this.serial, required this.state});

  /// USB serial (e.g. `R58M12ABCDE`) or network address (e.g. `192.168.43.1:5555`).
  final String serial;

  final AdbDeviceState state;

  /// How adb reaches this device (see [AdbTransport]).
  AdbTransport get transport => AdbTransport.of(serial);

  /// The hardware serial, when the adb serial carries it; see
  /// [AdbTransport.hardwareSerialOf].
  String? get hardwareSerial => AdbTransport.hardwareSerialOf(serial);

  /// True when this entry is an address added with `adb connect` (`ip:port`).
  /// Wireless-debugging (mDNS) entries and emulators are not; use [transport].
  bool get isNetwork => transport == AdbTransport.network;

  /// Whether Go Wireless and handoff apply: only a phone connected by USB can
  /// be switched to TCP mode. Not an emulator, not a phone that is already
  /// wireless (an `ip:port` address or wireless debugging).
  bool get canGoWireless => transport == AdbTransport.usb;

  bool get isReady => state == AdbDeviceState.device;

  @override
  bool operator ==(Object other) =>
      other is AdbDevice && other.serial == serial && other.state == state;

  @override
  int get hashCode => Object.hash(serial, state);

  @override
  String toString() => 'AdbDevice($serial, ${state.name})';
}
