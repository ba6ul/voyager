import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/handoff.dart';
import 'package:scrcpy_daemon/src/scrcpy_launcher.dart';
import 'package:test/test.dart';

/// Mock launcher that records all launch() and stop() calls for verification.
class MockScrcpyLauncher implements ScrcpyLauncher {
  @override
  final String scrcpyPath = 'mock-scrcpy';

  @override
  final List<String> baseArgs = const [];

  @override
  final void Function(String serial, int exitCode)? onExit = null;

  final List<LaunchCall> launches = [];
  final List<String> stops = [];
  final Map<String, bool> _running = {};

  /// Serials that should fail to launch, to simulate scrcpy erroring out.
  final Set<String> failLaunches = {};

  @override
  Future<bool> launch(
    String serial, {
    String? windowTitle,
    List<String> extraArgs = const [],
  }) async {
    launches.add(LaunchCall(serial, windowTitle, extraArgs));
    if (failLaunches.contains(serial)) return false;
    _running[serial] = true;
    return true;
  }

  @override
  void stop(String serial) {
    stops.add(serial);
    _running.remove(serial);
  }

  @override
  void stopAll() {
    _running.clear();
  }

  @override
  bool isRunning(String serial) => _running[serial] ?? false;

  /// Helper: get the order of launches and stops as a readable trace.
  List<String> getEventTrace() {
    final events = <String>[];
    var launchIdx = 0;
    var stopIdx = 0;
    while (launchIdx < launches.length || stopIdx < stops.length) {
      if (launchIdx < launches.length &&
          (stopIdx >= stops.length ||
              launches[launchIdx].serial.compareTo(stops[stopIdx]) <= 0)) {
        final call = launches[launchIdx];
        events.add('launch(${call.serial})');
        launchIdx++;
      } else {
        events.add('stop(${stops[stopIdx]})');
        stopIdx++;
      }
    }
    return events;
  }
}

class LaunchCall {
  LaunchCall(this.serial, this.windowTitle, this.extraArgs);
  final String serial;
  final String? windowTitle;
  final List<String> extraArgs;
}

// FakeAdbServer's `ip route` shell response always resolves to this address
// (see packages/core/lib/src/testing/fake_server.dart), so the same-WiFi path
// in handoff() is what these tests exercise; the hotspot-gateway fallback
// would shell out to the real Windows routing table and isn't stubbed here.
const _phoneWifiSerial = '192.168.1.42:5555';

void main() {
  group('Handoff (USB -> Wireless)', () {
    late FakeAdbServer server;
    late AdbClient client;
    late MockScrcpyLauncher launcher;

    setUp(() async {
      server = await FakeAdbServer.start();
      client = AdbClient(port: server.port);
      launcher = MockScrcpyLauncher();
    });

    tearDown(() => server.close());

    test('handoff opens wireless window before closing USB window', () async {
      // USB window already open before the handoff is requested.
      await launcher.launch('FAKESERIAL', windowTitle: 'Pixel 7');

      // The wireless address is already reachable by the time handoff polls
      // for it, so the same-WiFi connect succeeds on the first check.
      server.setDevices('FAKESERIAL\tdevice\n$_phoneWifiSerial\tdevice\n');

      final result = await handoff(
        client: client,
        launcher: launcher,
        usbSerial: 'FAKESERIAL',
        deviceName: 'Pixel 7',
        timeout: const Duration(seconds: 5),
      );

      expect(result, _phoneWifiSerial);
      expect(launcher.stops, ['FAKESERIAL']);
      expect(
        launcher.getEventTrace(),
        ['launch(FAKESERIAL)', 'launch($_phoneWifiSerial)', 'stop(FAKESERIAL)'],
      );
    });

    test('handoff times out if wireless never appears', () async {
      await launcher.launch('FAKESERIAL', windowTitle: 'Pixel 7');
      // Devices list is left at the default (USB only) for the whole test,
      // so neither the same-WiFi address nor any hotspot gateway ever shows
      // up as ready; handoff() must give up once its timeout elapses.

      final result = await handoff(
        client: client,
        launcher: launcher,
        usbSerial: 'FAKESERIAL',
        deviceName: 'Pixel 7',
        timeout: const Duration(seconds: 2),
      );

      expect(result, isNull);
      expect(launcher.launches.map((c) => c.serial), ['FAKESERIAL']);
      expect(launcher.stops, isEmpty);
      expect(launcher.isRunning('FAKESERIAL'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('handoff reverts if new window fails to launch', () async {
      await launcher.launch('FAKESERIAL', windowTitle: 'Pixel 7');
      launcher.failLaunches.add(_phoneWifiSerial);
      server.setDevices('FAKESERIAL\tdevice\n$_phoneWifiSerial\tdevice\n');

      final result = await handoff(
        client: client,
        launcher: launcher,
        usbSerial: 'FAKESERIAL',
        deviceName: 'Pixel 7',
        timeout: const Duration(seconds: 5),
      );

      expect(result, isNull);
      expect(launcher.getEventTrace(), ['launch(FAKESERIAL)', 'launch($_phoneWifiSerial)']);
      expect(launcher.stops, isEmpty);
      expect(launcher.isRunning('FAKESERIAL'), isTrue);
    });
  });
}
