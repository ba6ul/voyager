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

  group('WirelessReconnector.retryNow', () {
    late FakeAdbServer server;
    late WirelessReconnector reconnector;

    setUp(() async {
      server = await FakeAdbServer.start();
      reconnector = WirelessReconnector(client: AdbClient(port: server.port));
    });

    tearDown(() => server.close());

    ReconnectSnapshot snapshot({
      Map<String, AdbDevice> live = const {},
      Set<String> inFlight = const {},
    }) =>
        ReconnectSnapshot(
          cached: {_cached.usbSerial: _cached},
          live: live,
          handoffInFlight: inFlight,
        );

    test('reports reconnected when adb connect succeeds', () async {
      expect(await reconnector.retryNow(_cached, snapshot()),
          ManualRetryOutcome.reconnected);
    });

    test('reports unreachable when adb cannot be asked or does not answer',
        () async {
      final dead = WirelessReconnector(client: AdbClient(port: 1));

      expect(await dead.retryNow(_cached, snapshot()),
          ManualRetryOutcome.unreachable);
    });

    test('reports skipped when the phone is already live over USB', () async {
      final outcome = await reconnector.retryNow(
        _cached,
        snapshot(live: {
          _cached.usbSerial: AdbDevice(
              serial: _cached.usbSerial, state: AdbDeviceState.device),
        }),
      );

      expect(outcome, ManualRetryOutcome.skipped);
    });

    test('reports skipped while a wireless flow for it is in flight', () async {
      expect(
        await reconnector.retryNow(
            _cached, snapshot(inFlight: {_cached.usbSerial})),
        ManualRetryOutcome.skipped,
      );
    });

    test('still tries while a periodic tick is running', () async {
      // runOnce returns immediately when a tick is already in flight; a
      // manual retry must not be swallowed by that.
      final tick = reconnector.runOnce(snapshot());

      expect(await reconnector.retryNow(_cached, snapshot()),
          ManualRetryOutcome.reconnected);
      await tick;
    });
  });
}
