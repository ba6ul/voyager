import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

AdbDevice _device(String serial) =>
    AdbDevice(serial: serial, state: AdbDeviceState.device);

void main() {
  group('AdbTransport.of', () {
    test('a bare hardware serial is USB', () {
      // From the daemon's cache of the owner's phone, written when it was on USB.
      expect(AdbTransport.of('65261XEA33U4D0'), AdbTransport.usb);
      expect(AdbTransport.of('R58M12ABCDE'), AdbTransport.usb);
      expect(AdbTransport.of('0123456789ABCDEF'), AdbTransport.usb);
    });

    test('an address added with adb connect is a network device', () {
      expect(AdbTransport.of('192.168.43.1:5555'), AdbTransport.network);
      expect(AdbTransport.of('192.168.1.6:5555'), AdbTransport.network);
      expect(AdbTransport.of('[fe80::1]:5555'), AdbTransport.network);
      // adb also lists a connected emulator's TCP port this way.
      expect(AdbTransport.of('127.0.0.1:5555'), AdbTransport.network);
    });

    test('a wireless-debugging name is mDNS', () {
      // Observed live on the owner's Pixel 10a on 2026-10-28.
      expect(
        AdbTransport.of('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp'),
        AdbTransport.mdns,
      );
    });

    test('an emulator serial is an emulator', () {
      // Observed live: emulator-5554 from a booted AVD on 2026-10-28.
      expect(AdbTransport.of('emulator-5554'), AdbTransport.emulator);
      expect(AdbTransport.of('emulator-5556'), AdbTransport.emulator);
    });

    test('lookalikes are not misclassified', () {
      // Not an emulator: no port number.
      expect(AdbTransport.of('emulator-'), AdbTransport.usb);
      expect(AdbTransport.of('emulator-abc'), AdbTransport.usb);
      expect(AdbTransport.of('emulator-5554x'), AdbTransport.usb);
      // A real serial that merely contains the word.
      expect(AdbTransport.of('myemulator-5554'), AdbTransport.usb);
      // adb-... without the wireless-debugging service name.
      expect(AdbTransport.of('adb-65261XEA33U4D0-HvLNB1'), AdbTransport.usb);
      // Pairing service is not a connect transport; it has no device serial
      // shape here and is not treated as mDNS connect.
      expect(
        AdbTransport.of('adb-65261XEA33U4D0-HvLNB1._adb-tls-pairing._tcp'),
        AdbTransport.usb,
      );
      // Service name but nothing between the prefix and the suffix.
      expect(AdbTransport.of('adb-._adb-tls-connect._tcp'), AdbTransport.usb);
      expect(AdbTransport.of('adb--x._adb-tls-connect._tcp'), AdbTransport.usb);
    });
  });

  group('AdbTransport.hardwareSerialOf', () {
    test('USB carries its own serial', () {
      expect(AdbTransport.hardwareSerialOf('65261XEA33U4D0'), '65261XEA33U4D0');
    });

    test('mDNS carries the serial embedded in the name', () {
      expect(
        AdbTransport.hardwareSerialOf(
            'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp'),
        '65261XEA33U4D0',
      );
    });

    test('a hyphen inside the serial is kept; only the last segment is the '
        'suffix', () {
      expect(
        AdbTransport.hardwareSerialOf('adb-ABC-123-xyz._adb-tls-connect._tcp'),
        'ABC-123',
      );
    });

    test('network and emulator serials say nothing about which device', () {
      expect(AdbTransport.hardwareSerialOf('192.168.43.1:5555'), isNull);
      // The emulator's own ro.serialno (EMULATOR36X4X9X0 when observed) is not
      // its adb serial, so it cannot be recovered from emulator-5554.
      expect(AdbTransport.hardwareSerialOf('emulator-5554'), isNull);
    });
  });

  group('AdbDevice', () {
    test('Go Wireless and handoff apply to USB only', () {
      expect(_device('65261XEA33U4D0').canGoWireless, isTrue);
      expect(_device('192.168.1.6:5555').canGoWireless, isFalse);
      expect(
        _device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp')
            .canGoWireless,
        isFalse,
      );
      expect(_device('emulator-5554').canGoWireless, isFalse);
    });

    test('isNetwork keeps meaning "an ip:port address added with connect"', () {
      expect(_device('192.168.43.1:5555').isNetwork, isTrue);
      expect(_device('65261XEA33U4D0').isNetwork, isFalse);
      expect(
        _device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp').isNetwork,
        isFalse,
      );
      expect(_device('emulator-5554').isNetwork, isFalse);
    });

    test('exposes transport and hardware serial', () {
      final mdns =
          _device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp');
      expect(mdns.transport, AdbTransport.mdns);
      expect(mdns.hardwareSerial, '65261XEA33U4D0');
      expect(_device('emulator-5554').transport, AdbTransport.emulator);
    });
  });
}
