import 'adb_device.dart';

/// Reads `ro.serialno` over the transport named by an adb serial, e.g.
/// [AdbClient.serialNumber].
typedef SerialNumberReader = Future<String?> Function(String serial);

/// Which physical phone a device entry is: its hardware serial
/// (`ro.serialno`), the same value whichever way adb reaches the phone.
///
/// One phone can be listed under several serials at once (USB,
/// wireless debugging, an `ip:port` address). Code that has to treat those
/// as the same phone compares identities, not serials.
abstract final class DeviceIdentity {
  /// The identity of [device], or null when it cannot be known.
  ///
  /// - USB and wireless debugging: the serial carries it
  ///   ([AdbDevice.hardwareSerial]); nothing is sent to the device.
  /// - `ip:port`: the address says nothing about which phone answers it, so
  ///   [readSerialNumber] asks the device over that address. Only for a
  ///   device in `device` state; an offline or unauthorized entry cannot
  ///   answer. Errors from [readSerialNumber] propagate, and it has no
  ///   timeout of its own (#50): callers apply one.
  /// - Emulator: null. Its `ro.serialno` is not tied to its adb serial, and
  ///   it is never one of a phone's transports.
  static Future<String?> resolve(
    AdbDevice device, {
    required SerialNumberReader readSerialNumber,
  }) async {
    switch (device.transport) {
      case AdbTransport.usb:
      case AdbTransport.mdns:
        return device.hardwareSerial;
      case AdbTransport.network:
        if (!device.isReady) return null;
        return readSerialNumber(device.serial);
      case AdbTransport.emulator:
        return null;
    }
  }
}
