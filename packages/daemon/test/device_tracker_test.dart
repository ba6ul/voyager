import 'dart:async';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/device_tracker.dart';
import 'package:test/test.dart';

AdbDevice _device(String serial, [AdbDeviceState state = AdbDeviceState.device]) =>
    AdbDevice(serial: serial, state: state);

void main() {
  late FakeAdbServer server;
  late Map<String, String> modelNames;
  late List<(String serial, String name)> ready;
  late List<String> gone;
  late List<String> logs;
  late int changes;
  Completer<void>? readySignal;

  DeviceTracker newTracker({
    Duration modelTimeout = const Duration(milliseconds: 200),
    Future<void> Function(AdbDevice, String)? onReady,
  }) =>
      DeviceTracker(
        client: AdbClient(port: server.port),
        modelNames: modelNames,
        modelTimeout: modelTimeout,
        onReady: onReady ??
            (device, name) async {
              ready.add((device.serial, name));
              readySignal?.complete();
            },
        onGone: gone.add,
        onChanged: (_) => changes++,
        log: logs.add,
      );

  setUp(() async {
    server = await FakeAdbServer.start();
    modelNames = {};
    ready = [];
    gone = [];
    logs = [];
    changes = 0;
    readySignal = null;
  });

  tearDown(() => server.close());

  group('a device that becomes ready', () {
    test('is announced with its model name, which is remembered', () async {
      readySignal = Completer<void>();
      final tracker = newTracker();

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await readySignal!.future.timeout(const Duration(seconds: 2));

      expect(ready, [('FAKESERIAL', 'Pixel 7')]);
      expect(modelNames, {'FAKESERIAL': 'Pixel 7'});
      expect(tracker.known.keys, ['FAKESERIAL']);
    });

    test('is announced once, not again for an unchanged snapshot', () async {
      readySignal = Completer<void>();
      final tracker = newTracker();

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await readySignal!.future.timeout(const Duration(seconds: 2));
      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(ready, hasLength(1));
    });

    test('is announced again after dropping to offline and coming back',
        () async {
      var announced = Completer<void>();
      final tracker = newTracker(onReady: (device, name) async {
        ready.add((device.serial, name));
        announced.complete();
      });

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await announced.future.timeout(const Duration(seconds: 2));
      tracker.handleSnapshot([_device('FAKESERIAL', AdbDeviceState.offline)]);
      announced = Completer<void>();
      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await announced.future.timeout(const Duration(seconds: 2));

      expect(ready, hasLength(2));
      expect(logs, contains('[~] FAKESERIAL: device -> offline'));
    });

    test('a device that is not ready is not announced', () async {
      final tracker = newTracker();

      tracker.handleSnapshot([_device('FAKESERIAL', AdbDeviceState.unauthorized)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(ready, isEmpty);
      expect(logs.single, contains('unauthorized'));
    });
  });

  group('a slow model lookup', () {
    test('does not hold up the next snapshot', () async {
      // Regression for #15: onReady was awaited inside the tracking loop, and
      // its first step (the model lookup) has no read timeout, so one stalled
      // device froze disconnects, state changes and broadcasts for all.
      server.stallModelReplies(true);
      final tracker = newTracker(modelTimeout: const Duration(seconds: 30));

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      // Returned at once although the model lookup is still pending.
      expect(ready, isEmpty);

      tracker.handleSnapshot([]);

      expect(gone, ['FAKESERIAL']);
      expect(changes, 2);
      expect(tracker.known, isEmpty);
    });

    test('is announced under its serial once the timeout passes', () async {
      server.stallModelReplies(true);
      readySignal = Completer<void>();
      final tracker = newTracker(modelTimeout: const Duration(milliseconds: 150));

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await readySignal!.future.timeout(const Duration(seconds: 3));

      expect(ready, [('FAKESERIAL', 'FAKESERIAL')]);
      expect(modelNames, isEmpty, reason: 'a fallback is not stored as a model');
    });

    test('is not announced if the device disappeared while we waited',
        () async {
      server.stallModelReplies(true);
      final tracker = newTracker(modelTimeout: const Duration(milliseconds: 150));

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      tracker.handleSnapshot([]);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(ready, isEmpty);
    });
  });

  group('a failing model lookup', () {
    test('does not throw out of the snapshot and still announces the device',
        () async {
      // Regression for #15: the throw (a device that drops between the
      // snapshot and the call) escaped into the loop's catch-all, which logged
      // "adb server unreachable", re-subscribed, and, because `known` had
      // already been updated, never auto-launched the device.
      readySignal = Completer<void>();
      final tracker = newTracker();

      // The fake answers FAIL for any serial but FAKESERIAL, like adb does for
      // a device that is no longer there.
      expect(() => tracker.handleSnapshot([_device('GONE123')]), returnsNormally);
      await readySignal!.future.timeout(const Duration(seconds: 2));

      expect(ready, [('GONE123', 'GONE123')]);
      expect(modelNames, isEmpty);
      expect(logs.any((l) => l.contains('adb server unreachable')), isFalse);
    });

    test('an onReady that throws is logged and the tracker keeps working',
        () async {
      final failed = Completer<void>();
      final tracker = newTracker(onReady: (device, name) async {
        failed.complete();
        throw StateError('launch exploded');
      });

      tracker.handleSnapshot([_device('FAKESERIAL')]);
      await failed.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(logs.any((l) => l.contains('launch exploded')), isTrue);
      // The next snapshot is still handled normally.
      tracker.handleSnapshot([]);
      expect(gone, ['FAKESERIAL']);
    });
  });

  group('snapshots', () {
    test('report a vanished device and update the known map', () async {
      final tracker = newTracker();

      tracker.handleSnapshot([_device('A'), _device('B', AdbDeviceState.offline)]);
      tracker.handleSnapshot([_device('B', AdbDeviceState.offline)]);

      expect(gone, ['A']);
      expect(tracker.known.keys, ['B']);
      expect(logs, contains('[-] A disconnected'));
      expect(changes, 2);
    });

    test('hand the caller an immutable view that later snapshots do not mutate',
        () async {
      final tracker = newTracker();
      tracker.handleSnapshot([_device('A', AdbDeviceState.offline)]);
      final first = tracker.known;

      tracker.handleSnapshot([_device('B', AdbDeviceState.offline)]);

      expect(first.keys, ['A'], reason: 'callers iterate it across awaits');
      expect(tracker.known.keys, ['B']);
    });
  });
}
