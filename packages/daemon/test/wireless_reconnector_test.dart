import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/known_devices.dart';
import 'package:scrcpy_daemon/src/wireless_reconnector.dart';
import 'package:test/test.dart';

const _cached = KnownWirelessDevice(
  usbSerial: 'FAKESERIAL',
  model: 'Pixel 7',
  lastIp: '192.168.1.42',
  lastPort: 5555,
);

void main() {
  group('candidatesToRetry', () {
    test('includes a cached device against an empty live map (cold start)', () {
      final result = candidatesToRetry(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: const {},
      ));

      expect(result, [_cached]);
    });

    test('excludes a device already live and ready over the network', () {
      final result = candidatesToRetry(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: {
          _cached.networkSerial: AdbDevice(
            serial: _cached.networkSerial,
            state: AdbDeviceState.device,
          ),
        },
        handoffInFlight: const {},
      ));

      expect(result, isEmpty);
    });

    test('excludes a device already live and ready over USB', () {
      final result = candidatesToRetry(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: {
          _cached.usbSerial: AdbDevice(
            serial: _cached.usbSerial,
            state: AdbDeviceState.device,
          ),
        },
        handoffInFlight: const {},
      ));

      expect(result, isEmpty);
    });

    test('excludes a device with a handoff currently in flight', () {
      final result = candidatesToRetry(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: {_cached.usbSerial},
      ));

      expect(result, isEmpty);
    });

    test('does not exclude a USB entry that is present but not ready', () {
      final result = candidatesToRetry(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: {
          _cached.usbSerial: AdbDevice(
            serial: _cached.usbSerial,
            state: AdbDeviceState.offline,
          ),
        },
        handoffInFlight: const {},
      ));

      expect(result, [_cached]);
    });
  });

  group('WirelessReconnector.runOnce', () {
    late FakeAdbServer server;
    late AdbClient client;
    late WirelessReconnector reconnector;

    setUp(() async {
      server = await FakeAdbServer.start();
      client = AdbClient(port: server.port);
      reconnector = WirelessReconnector(client: client);
    });

    tearDown(() => server.close());

    test('reconnects a cached candidate and returns its network serial',
        () async {
      final result = await reconnector.runOnce(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: const {},
      ));

      expect(result, [_cached.networkSerial]);
    });

    test('does not attempt an excluded candidate', () async {
      final result = await reconnector.runOnce(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: {_cached.usbSerial},
      ));

      expect(result, isEmpty);
    });

    test('a concurrent call while one is in flight returns immediately',
        () async {
      final first = reconnector.runOnce(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: const {},
      ));

      final second = await reconnector.runOnce(ReconnectSnapshot(
        cached: {_cached.usbSerial: _cached},
        live: const {},
        handoffInFlight: const {},
      ));

      expect(second, isEmpty);
      await first;
    });
  });
}
