import 'dart:io';

import 'package:scrcpy_daemon/src/known_devices.dart';
import 'package:test/test.dart';

void main() {
  group('KnownWirelessDevice JSON', () {
    test('round-trips through toJson/fromJson', () {
      const device = KnownWirelessDevice(
        usbSerial: 'FAKESERIAL',
        model: 'Pixel 7',
        lastIp: '192.168.1.42',
        lastPort: 5555,
      );

      final restored = KnownWirelessDevice.fromJson(device.toJson());

      expect(restored.usbSerial, device.usbSerial);
      expect(restored.model, device.model);
      expect(restored.lastIp, device.lastIp);
      expect(restored.lastPort, device.lastPort);
      expect(restored.networkSerial, '192.168.1.42:5555');
    });
  });

  group('KnownDevicesStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('known_devices_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    File cacheFile() => File('${tempDir.path}/known_wireless_devices.json');

    test('load returns empty map when the file does not exist', () async {
      final result = await KnownDevicesStore.load(file: cacheFile());
      expect(result, isEmpty);
    });

    test('load returns empty map for corrupt JSON without throwing', () async {
      cacheFile().writeAsStringSync('{not valid json');
      final result = await KnownDevicesStore.load(file: cacheFile());
      expect(result, isEmpty);
    });

    test('save then load round-trips devices keyed by usbSerial', () async {
      const a = KnownWirelessDevice(
        usbSerial: 'SERIAL_A',
        model: 'Pixel 7',
        lastIp: '192.168.1.42',
        lastPort: 5555,
      );
      const b = KnownWirelessDevice(
        usbSerial: 'SERIAL_B',
        model: 'Pixel 8',
        lastIp: '192.168.43.1',
        lastPort: 5555,
      );

      await KnownDevicesStore.save({a.usbSerial: a, b.usbSerial: b},
          file: cacheFile());
      final loaded = await KnownDevicesStore.load(file: cacheFile());

      expect(loaded.keys, unorderedEquals(['SERIAL_A', 'SERIAL_B']));
      expect(loaded['SERIAL_A']!.networkSerial, '192.168.1.42:5555');
      expect(loaded['SERIAL_B']!.model, 'Pixel 8');
    });

    test('save creates the parent directory if needed', () async {
      final nested = File('${tempDir.path}/nested/known_wireless_devices.json');
      const device = KnownWirelessDevice(
        usbSerial: 'SERIAL_A',
        model: 'Pixel 7',
        lastIp: '192.168.1.42',
        lastPort: 5555,
      );

      await KnownDevicesStore.save({device.usbSerial: device}, file: nested);

      expect(nested.existsSync(), isTrue);
    });
  });
}
