import 'dart:convert';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('encodeRequest', () {
    test('prefixes payload with 4-digit hex length', () {
      final bytes = AdbProtocol.encodeRequest('host:version');
      expect(ascii.decode(bytes), '000chost:version');
    });

    test('handles longer services', () {
      final service = 'host:connect:192.168.43.1:5555';
      final bytes = AdbProtocol.encodeRequest(service);
      expect(ascii.decode(bytes.sublist(0, 4)),
          service.length.toRadixString(16).padLeft(4, '0'));
      expect(ascii.decode(bytes.sublist(4)), service);
    });
  });

  group('parseHexLength', () {
    test('parses valid prefix', () {
      expect(AdbProtocol.parseHexLength(ascii.encode('001d')), 29);
      expect(AdbProtocol.parseHexLength(ascii.encode('0000')), 0);
      expect(AdbProtocol.parseHexLength(ascii.encode('ffff')), 65535);
    });

    test('rejects garbage', () {
      expect(() => AdbProtocol.parseHexLength(ascii.encode('zzzz')),
          throwsA(isA<AdbProtocolException>()));
      expect(() => AdbProtocol.parseHexLength(ascii.encode('12')),
          throwsA(isA<AdbProtocolException>()));
    });
  });

  group('parseDeviceList', () {
    test('parses tab-separated entries', () {
      final devices = AdbProtocol.parseDeviceList(
        'R58M12ABCDE\tdevice\n192.168.43.1:5555\toffline\n',
      );
      expect(devices, hasLength(2));
      expect(devices[0].serial, 'R58M12ABCDE');
      expect(devices[0].state, AdbDeviceState.device);
      expect(devices[0].isNetwork, isFalse);
      expect(devices[1].serial, '192.168.43.1:5555');
      expect(devices[1].state, AdbDeviceState.offline);
      expect(devices[1].isNetwork, isTrue);
    });

    test('empty payload means no devices', () {
      expect(AdbProtocol.parseDeviceList(''), isEmpty);
      expect(AdbProtocol.parseDeviceList('\n'), isEmpty);
    });

    test('unauthorized state is surfaced', () {
      final devices = AdbProtocol.parseDeviceList('SER123\tunauthorized\n');
      expect(devices.single.state, AdbDeviceState.unauthorized);
      expect(devices.single.isReady, isFalse);
    });

    test('unknown states do not crash', () {
      final devices = AdbProtocol.parseDeviceList('SER123\tsideload\n');
      expect(devices.single.state, AdbDeviceState.unknown);
    });
  });

  group('parseWlanIp', () {
    test('extracts src address on wlan0', () {
      const output =
          '192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42\n'
          '10.0.0.0/8 dev rmnet0 proto kernel scope link src 10.12.34.56';
      expect(AdbProtocol.parseWlanIp(output), '192.168.1.42');
    });

    test('ignores non-wlan interfaces', () {
      const output =
          '10.0.0.0/8 dev rmnet0 proto kernel scope link src 10.12.34.56';
      expect(AdbProtocol.parseWlanIp(output), isNull);
    });

    test('handles wlan1 and extra route flags', () {
      const output =
          '192.168.0.0/24 dev wlan1 proto kernel scope link src 192.168.0.7 metric 600';
      expect(AdbProtocol.parseWlanIp(output), '192.168.0.7');
    });
  });

  group('connectSucceeded', () {
    test('accepts success messages', () {
      expect(AdbClient.connectSucceeded('connected to 192.168.43.1:5555'), isTrue);
      expect(
          AdbClient.connectSucceeded('already connected to 192.168.43.1:5555'),
          isTrue);
    });

    test('rejects failure messages', () {
      expect(
          AdbClient.connectSucceeded(
              'failed to connect to 192.168.43.1:5555'),
          isFalse);
      expect(AdbClient.connectSucceeded('cannot resolve host'), isFalse);
    });
  });
}
