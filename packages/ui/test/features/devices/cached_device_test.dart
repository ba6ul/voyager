import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/cached_device.dart';

void main() {
  // Same shape as a real cache entry: the USB serial the phone first went
  // wireless from, plus the address it was last reached on.
  const cached = CachedDevice(
    usbSerial: '65261XEA33U4D0',
    model: 'Pixel 10a',
    lastIp: '192.168.1.6',
    lastPort: 5555,
  );

  group('CachedDevice.isRepresentedBy', () {
    test('matches the wireless address it went wireless on', () {
      expect(cached.isRepresentedBy('192.168.1.6:5555'), isTrue);
    });

    test('matches its own USB serial', () {
      expect(cached.isRepresentedBy('65261XEA33U4D0'), isTrue);
    });

    test('matches the wireless-debugging (mDNS) form that embeds its serial',
        () {
      expect(
        cached.isRepresentedBy(
            'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp'),
        isTrue,
      );
    });

    test('does not match another phone', () {
      expect(cached.isRepresentedBy('R58M12ABCDE'), isFalse);
      expect(cached.isRepresentedBy('192.168.1.7:5555'), isFalse);
      expect(cached.isRepresentedBy('emulator-5554'), isFalse);
    });

    test('does not match an mDNS serial that only starts with the same text',
        () {
      // A different phone whose serial begins with this one's serial.
      expect(
        cached.isRepresentedBy(
            'adb-65261XEA33U4D0EXTRA-abc123._adb-tls-connect._tcp'),
        isFalse,
      );
      // Right prefix, but not the wireless-debugging service name.
      expect(cached.isRepresentedBy('adb-65261XEA33U4D0-abc123'), isFalse);
    });
  });
}
