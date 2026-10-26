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

/// How the daemon reaches a device. The daemon decides this and sends it as
/// `transport` in every device entry; [of] is only the fallback for a daemon
/// that does not send it yet, and applies the same rules as `AdbTransport` in
/// packages/core (the same example serials are tested on both sides).
enum DeviceTransport {
  /// A phone on a cable: the bare hardware serial.
  usb,

  /// An address added with `adb connect`, e.g. `192.168.43.1:5555`.
  network,

  /// Wireless debugging, e.g. `adb-<serial>-<suffix>._adb-tls-connect._tcp`.
  mdns,

  /// An Android emulator, e.g. `emulator-5554`.
  emulator;

  static final _emulator = RegExp(r'^emulator-\d+$');

  static DeviceTransport of(String serial) {
    if (_emulator.hasMatch(serial)) return emulator;
    if (serial.startsWith('adb-') &&
        serial.endsWith('._adb-tls-connect._tcp') &&
        _hasSerialAndSuffix(serial)) {
      return mdns;
    }
    if (serial.contains(':')) return network;
    return usb;
  }

  static bool _hasSerialAndSuffix(String serial) {
    final middle = serial.substring(
        'adb-'.length, serial.length - '._adb-tls-connect._tcp'.length);
    final dash = middle.lastIndexOf('-');
    return dash > 0 && dash < middle.length - 1;
  }

  /// The daemon's `transport` value, or null if it is missing or unknown.
  static DeviceTransport? parse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// A device as known to the daemon: USB serial (e.g. `R58M12ABCDE`) or
/// network address (e.g. `192.168.43.1:5555`).
class Device extends Equatable {
  const Device({
    required this.serial,
    required this.state,
    required this.mirroring,
    this.model,
    DeviceTransport? transport,
  }) : _transport = transport;

  final String serial;
  final DeviceState state;
  final String? model;

  final DeviceTransport? _transport;

  /// How the device is reached; decides which actions apply. What the daemon
  /// reported, or worked out from the serial if it reported nothing.
  DeviceTransport get transport => _transport ?? DeviceTransport.of(serial);

  /// Whether the daemon currently has a scrcpy window open for this serial.
  final bool mirroring;

  bool get isReady => state == DeviceState.device;

  /// Go Wireless and Handoff apply only to a phone connected by USB: not to an
  /// emulator, and not to a phone that is already wireless.
  bool get canGoWireless => transport == DeviceTransport.usb;

  /// Short note shown beside the serial, or null for plain USB.
  String? get transportLabel => switch (transport) {
        DeviceTransport.usb => null,
        DeviceTransport.network => 'wireless',
        DeviceTransport.mdns => 'wireless debugging',
        DeviceTransport.emulator => 'emulator',
      };

  @override
  List<Object?> get props => [serial, state, model, mirroring, transport];
}
