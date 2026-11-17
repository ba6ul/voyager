import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('AdbPairing.parseResponse', () {
    test('success carries the guid', () {
      final r = AdbPairing.parseResponse(
          'Successfully paired to 192.168.1.8:37123 [guid=adb-65261XEA33U4D0-HvLNB1]');
      expect(r.outcome, PairOutcome.paired);
      expect(r.guid, 'adb-65261XEA33U4D0-HvLNB1');
    });

    test('a password failure is a wrong code', () {
      expect(
          AdbPairing.parseResponse('Failed: Wrong password or connection was dropped.')
              .outcome,
          PairOutcome.wrongCode);
    });

    test('a pairing client that cannot start is unreachable', () {
      expect(AdbPairing.parseResponse('Failed: Unable to start pairing client.').outcome,
          PairOutcome.unreachable);
    });

    test('anything else is a failure with adb\'s own text', () {
      final r = AdbPairing.parseResponse('Failed: something new');
      expect(r.outcome, PairOutcome.failed);
      expect(r.message, 'Failed: something new');
      expect(AdbPairing.parseResponse('').message, 'no reply');
    });
  });

  group('validation', () {
    test('addresses', () {
      expect(AdbPairing.isValidAddress('192.168.1.8:37123'), isTrue);
      expect(AdbPairing.isValidAddress('192.168.1.8'), isFalse);
      expect(AdbPairing.isValidAddress('192.168.1.256:5'), isFalse);
      expect(AdbPairing.isValidAddress('192.168.1.8:99999'), isFalse);
    });

    test('codes', () {
      expect(AdbPairing.isValidCode('012345'), isTrue);
      expect(AdbPairing.isValidCode('12345'), isFalse);
      expect(AdbPairing.isValidCode('12345a'), isFalse);
    });
  });
}
