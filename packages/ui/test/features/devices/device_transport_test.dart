import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/data/models/device_model.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';

void main() {
  // The same serials as packages/core's adb_transport_test.dart: the UI's
  // fallback and the daemon's classification must agree on all of them.
  group('DeviceTransport.of (fallback)', () {
    const cases = <String, DeviceTransport>{
      '65261XEA33U4D0': DeviceTransport.usb,
      'R58M12ABCDE': DeviceTransport.usb,
      '192.168.43.1:5555': DeviceTransport.network,
      '[fe80::1]:5555': DeviceTransport.network,
      '127.0.0.1:5555': DeviceTransport.network,
      'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp': DeviceTransport.mdns,
      'emulator-5554': DeviceTransport.emulator,
      'emulator-5556': DeviceTransport.emulator,
      // lookalikes
      'emulator-': DeviceTransport.usb,
      'emulator-abc': DeviceTransport.usb,
      'emulator-5554x': DeviceTransport.usb,
      'myemulator-5554': DeviceTransport.usb,
      'adb-65261XEA33U4D0-HvLNB1': DeviceTransport.usb,
      'adb-65261XEA33U4D0-HvLNB1._adb-tls-pairing._tcp': DeviceTransport.usb,
      'adb-._adb-tls-connect._tcp': DeviceTransport.usb,
      'adb--x._adb-tls-connect._tcp': DeviceTransport.usb,
    };

    cases.forEach((serial, expected) {
      test('$serial is ${expected.name}', () {
        expect(DeviceTransport.of(serial), expected);
      });
    });
  });

  group('deviceFromJson', () {
    Map<String, dynamic> entry(String serial, {String? transport}) => {
          'serial': serial,
          'state': 'device',
          'mirroring': false,
          if (transport != null) 'transport': transport,
        };

    test('uses the transport the daemon reports', () {
      // The daemon is the source of truth, even where it differs from what the
      // fallback would guess.
      final device =
          deviceFromJson(entry('65261XEA33U4D0', transport: 'emulator'));

      expect(device.transport, DeviceTransport.emulator);
    });

    test('works the transport out itself when an older daemon sends none', () {
      final device = deviceFromJson(
          entry('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp'));

      expect(device.transport, DeviceTransport.mdns);
    });

    test('ignores an unknown transport value from a newer daemon', () {
      final device =
          deviceFromJson(entry('emulator-5554', transport: 'bluetooth'));

      expect(device.transport, DeviceTransport.emulator);
    });
  });

  group('Device', () {
    Device device(String serial) =>
        Device(serial: serial, state: DeviceState.device, mirroring: false);

    test('Go Wireless and Handoff apply to USB only', () {
      expect(device('65261XEA33U4D0').canGoWireless, isTrue);
      expect(device('192.168.1.6:5555').canGoWireless, isFalse);
      expect(
        device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp').canGoWireless,
        isFalse,
      );
      expect(device('emulator-5554').canGoWireless, isFalse);
    });

    test('labels every kind except plain USB', () {
      expect(device('65261XEA33U4D0').transportLabel, isNull);
      expect(device('192.168.1.6:5555').transportLabel, 'wireless');
      expect(
        device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp')
            .transportLabel,
        'wireless debugging',
      );
      expect(device('emulator-5554').transportLabel, 'emulator');
    });

    test('the transport takes part in equality', () {
      const a = Device(
          serial: 'X', state: DeviceState.device, mirroring: false);
      const b = Device(
          serial: 'X',
          state: DeviceState.device,
          mirroring: false,
          transport: DeviceTransport.emulator);

      expect(a == b, isFalse);
    });
  });
}
