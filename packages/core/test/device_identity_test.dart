import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

AdbDevice _device(String serial,
        [AdbDeviceState state = AdbDeviceState.device]) =>
    AdbDevice(serial: serial, state: state);

void main() {
  group('DeviceIdentity.resolve', () {
    late List<String> asked;
    late String? answer;

    Future<String?> reader(String serial) async {
      asked.add(serial);
      return answer;
    }

    setUp(() {
      asked = [];
      answer = '65261XEA33U4D0';
    });

    test('USB: the serial is the identity, nothing is asked', () async {
      expect(
        await DeviceIdentity.resolve(_device('65261XEA33U4D0'),
            readSerialNumber: reader),
        '65261XEA33U4D0',
      );
      expect(asked, isEmpty);
    });

    test('wireless debugging: the embedded serial, nothing is asked', () async {
      // The name observed live on the owner's Pixel 10a.
      expect(
        await DeviceIdentity.resolve(
            _device('adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp'),
            readSerialNumber: reader),
        '65261XEA33U4D0',
      );
      expect(asked, isEmpty);
    });

    test('ip:port: asks the device over that address', () async {
      expect(
        await DeviceIdentity.resolve(_device('192.168.1.8:5555'),
            readSerialNumber: reader),
        '65261XEA33U4D0',
      );
      expect(asked, ['192.168.1.8:5555']);
    });

    test('ip:port: a device that reports no serial has no identity', () async {
      answer = null;
      expect(
        await DeviceIdentity.resolve(_device('192.168.1.8:5555'),
            readSerialNumber: reader),
        isNull,
      );
    });

    test('ip:port not in device state: unknown, nothing is asked', () async {
      for (final state in [
        AdbDeviceState.offline,
        AdbDeviceState.unauthorized,
      ]) {
        expect(
          await DeviceIdentity.resolve(_device('192.168.1.8:5555', state),
              readSerialNumber: reader),
          isNull,
        );
      }
      expect(asked, isEmpty);
    });

    test('ip:port: a failed read propagates', () async {
      Future<String?> failing(String _) async =>
          throw const AdbServerException('device offline');
      expect(
        DeviceIdentity.resolve(_device('192.168.1.8:5555'),
            readSerialNumber: failing),
        throwsA(isA<AdbServerException>()),
      );
    });

    test('emulator: no identity, nothing is asked', () async {
      expect(
        await DeviceIdentity.resolve(_device('emulator-5554'),
            readSerialNumber: reader),
        isNull,
      );
      expect(asked, isEmpty);
    });
  });
}
