import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/in_flight_operations.dart';
import 'package:scrcpy_daemon/src/known_devices.dart';
import 'package:scrcpy_daemon/src/wireless_reconnector.dart';
import 'package:test/test.dart';

void main() {
  group('InFlightOperations', () {
    late InFlightOperations inFlight;

    setUp(() => inFlight = InFlightOperations());

    test('the first request for a phone starts', () {
      expect(inFlight.tryStart('A', InFlightOperations.goWireless), isNull);
      expect(inFlight.runningFor('A'), InFlightOperations.goWireless);
    });

    test('a second Go Wireless for the same phone is turned away', () {
      inFlight.tryStart('A', InFlightOperations.goWireless);

      expect(inFlight.tryStart('A', InFlightOperations.goWireless),
          InFlightOperations.goWireless);
      expect(inFlight.runningFor('A'), InFlightOperations.goWireless);
    });

    test('a handoff while Go Wireless runs is turned away, and the other way '
        'round', () {
      inFlight.tryStart('A', InFlightOperations.goWireless);
      expect(inFlight.tryStart('A', InFlightOperations.handoff),
          InFlightOperations.goWireless);

      inFlight.finish('A');
      inFlight.tryStart('A', InFlightOperations.handoff);
      expect(inFlight.tryStart('A', InFlightOperations.goWireless),
          InFlightOperations.handoff);
    });

    test('different phones do not block each other', () {
      expect(inFlight.tryStart('A', InFlightOperations.goWireless), isNull);
      expect(inFlight.tryStart('B', InFlightOperations.handoff), isNull);
      expect(inFlight.serials, {'A', 'B'});
    });

    test('finishing releases the phone, and finishing twice is harmless', () {
      inFlight.tryStart('A', InFlightOperations.goWireless);

      inFlight.finish('A');
      inFlight.finish('A');

      expect(inFlight.runningFor('A'), isNull);
      expect(inFlight.tryStart('A', InFlightOperations.handoff), isNull);
    });

    test('serials is a copy, not a live view', () {
      inFlight.tryStart('A', InFlightOperations.goWireless);
      final snapshot = inFlight.serials;

      inFlight.finish('A');

      expect(snapshot, {'A'});
      expect(inFlight.serials, isEmpty);
    });
  });

  group('the reconnector and an in-flight Go Wireless', () {
    test('leaves the phone alone while the operation runs, then resumes', () {
      const cached = KnownWirelessDevice(
        usbSerial: 'FAKESERIAL',
        model: 'Pixel 7',
        lastIp: '192.168.1.42',
        lastPort: 5555,
      );
      final inFlight = InFlightOperations();
      ReconnectSnapshot snapshot() => ReconnectSnapshot(
            cached: {cached.usbSerial: cached},
            live: <String, AdbDevice>{},
            handoffInFlight: inFlight.serials,
          );

      expect(candidatesToRetry(snapshot()), [cached]);

      inFlight.tryStart('FAKESERIAL', InFlightOperations.goWireless);
      expect(candidatesToRetry(snapshot()), isEmpty,
          reason: 'Go Wireless is already retrying this address itself');

      inFlight.finish('FAKESERIAL');
      expect(candidatesToRetry(snapshot()), [cached]);
    });
  });
}
