@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_ipc/scrcpy_ipc.dart';
import 'package:test/test.dart';

import 'support/daemon_harness.dart';

/// Runs the real daemon as a child process against the repository's fake adb
/// server, to check the failure paths from #14 end to end: whatever goes wrong
/// in a fire-and-forget path, the daemon must stay up and keep answering IPC.
///
/// Nothing here touches a real adb server, scrcpy or a phone (see
/// DaemonHarness).
void main() {
  late FakeAdbServer adb;
  DaemonHarness? daemon;

  setUp(() async {
    adb = await FakeAdbServer.start();
  });

  tearDown(() async {
    await daemon?.stop();
    daemon = null;
    await adb.close();
  });

  Future<DaemonHarness> startDaemon({
    bool autoLaunch = false,
    String? adbPath,
    int? adbPort,
    String? scrcpyPath,
    List<Map<String, dynamic>> savedWireless = const [],
  }) async {
    final d = await DaemonHarness.start(
      adbPort: adbPort ?? adb.port,
      autoLaunch: autoLaunch,
      adbPath: adbPath,
      scrcpyPath: scrcpyPath,
      savedWireless: savedWireless,
    );
    daemon = d;
    return d;
  }

  Future<void> expectStillServing(DaemonHarness d,
      {int devices = 1}) async {
    expect(d.isAlive, isTrue, reason: 'daemon exited:\n${d.log.join('\n')}');
    expect(await d.listDevices(), hasLength(devices));
    expect(d.isAlive, isTrue);
  }

  test('an invalid scrcpyPath during auto-launch is logged and the daemon '
      'keeps serving', () async {
    final d = await startDaemon(autoLaunch: true);

    // The fake adb reports one ready phone, so auto-launch fires and fails.
    await d.waitForLog('auto-launch for Pixel 7 failed');

    await expectStillServing(d);
  });

  test('the p key with an invalid scrcpyPath is logged and the daemon keeps '
      'serving', () async {
    final d = await startDaemon();
    await d.waitForLog('[+] Pixel 7');

    d.type('p');
    await d.waitForLog('command "p" failed');

    await expectStillServing(d);
  });

  test('the u key failing is logged and the daemon keeps serving', () async {
    // The fake adb answers FAIL to the usb: request, like a phone that
    // dropped between the check and the call.
    final d = await startDaemon();
    await d.waitForLog('[+] Pixel 7');

    d.type('u');
    await d.waitForLog('command "u" failed');

    await expectStillServing(d);
  });

  test('adb that cannot be restarted is logged and the daemon keeps serving',
      () async {
    final missingAdb =
        '${Directory.systemTemp.path}${Platform.pathSeparator}no-such-adb-binary';
    final d = await startDaemon(adbPath: missingAdb);
    await d.waitForLog('[+] Pixel 7');

    // The adb server goes away. The daemon's retry loop tries to start it
    // again, which fails because the adb binary does not exist.
    await adb.close();
    // Twice: the retry loop is still running after the first failure, not
    // just surviving it (an error that escaped the loop would log once at
    // most and end device tracking).
    await d.waitForLog('could not start the adb server', count: 2);

    expect(d.isAlive, isTrue);
    // The device list is the last known one; the point is that IPC answers.
    expect(await d.listDevices(), isA<List<Map<String, dynamic>>>());
    expect(d.isAlive, isTrue);
  });

  test('no adb server at startup is logged and the daemon stays up',
      () async {
    final missingAdb =
        '${Directory.systemTemp.path}${Platform.pathSeparator}no-such-adb-binary';
    final unusedPort = await DaemonHarness.freePort();
    final d = await startDaemon(adbPath: missingAdb, adbPort: unusedPort);

    await d.waitForLog('adb server not available yet');
    // The tracking loop is retrying, not stopped.
    await d.waitForLog('could not start the adb server', count: 2);

    expect(d.isAlive, isTrue);
    expect(await d.listDevices(), isEmpty);
  });

  // #56: the UI's Play/Stop follows `mirroring` in the devices snapshot, so
  // every change of it must be followed by a snapshot, launches included.
  group('mirroring state in the devices snapshot', () {
    // Stands in for scrcpy: accepts scrcpy's arguments and stays up until it
    // is killed (both read commands from stdin, which the daemon keeps open).
    final idleScrcpy = Platform.isWindows ? 'cmd.exe' : '/bin/sh';

    Future<void> waitFor(bool Function() condition, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('$what not seen in 20 s');
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    /// `mirroring` for FAKESERIAL in each devices snapshot received, in order.
    Future<(IpcClient, List<bool>)> watch(DaemonHarness d) async {
      await d.waitForLog('ipc: listening');
      final client = IpcClient();
      await client.connect(port: d.ipcPort);
      addTearDown(client.close);
      final mirroring = <bool>[];
      client.events
          .where((e) => e.event == IpcEvents.devices)
          .listen((e) {
        for (final device in (e.data['devices'] as List)
            .cast<Map<String, dynamic>>()) {
          if (device['serial'] == 'FAKESERIAL') {
            mirroring.add(device['mirroring'] as bool);
          }
        }
      });
      return (client, mirroring);
    }

    test('a launch over IPC is published, and so is the stop', () async {
      final d = await startDaemon(scrcpyPath: idleScrcpy);
      await d.waitForLog('[+] Pixel 7');
      final (client, mirroring) = await watch(d);
      await waitFor(() => mirroring.isNotEmpty, 'the catch-up snapshot');
      expect(mirroring, [false]);

      final launch =
          await client.send(IpcCommands.launch, {'serial': 'FAKESERIAL'});
      expect(launch.data['launched'], isTrue);
      await waitFor(() => mirroring.last, 'a snapshot with mirroring: true');

      // A second Play is not a new state, so it sends nothing new.
      final count = mirroring.length;
      final again =
          await client.send(IpcCommands.launch, {'serial': 'FAKESERIAL'});
      expect(again.data['alreadyRunning'], isTrue);

      await client.send(IpcCommands.stop, {'serial': 'FAKESERIAL'});
      await waitFor(() => !mirroring.last, 'a snapshot with mirroring: false');
      expect(mirroring.sublist(count), [false],
          reason: 'alreadyRunning must not broadcast; only the stop does');
      expect((await d.listDevices()).single['mirroring'], isFalse);
    });

    test('an auto-launch is published', () async {
      final d = await startDaemon(autoLaunch: true, scrcpyPath: idleScrcpy);
      // Connected before the debounced auto-launch (500 ms after the phone is
      // ready), so the snapshot with `true` can only come from the launch.
      final (client, mirroring) = await watch(d);

      await waitFor(() => mirroring.isNotEmpty && mirroring.last,
          'a snapshot with mirroring: true');
      expect(mirroring.first, isFalse,
          reason: 'the first snapshot predates the launch');

      await client.send(IpcCommands.stop, {'serial': 'FAKESERIAL'});
      await waitFor(() => !mirroring.last, 'a snapshot with mirroring: false');
    });

    test('a launch that fails leaves the phone not mirroring', () async {
      // The default scrcpyPath does not exist, so the start throws.
      final d = await startDaemon();
      await d.waitForLog('[+] Pixel 7');
      final (client, mirroring) = await watch(d);
      await waitFor(() => mirroring.isNotEmpty, 'the catch-up snapshot');

      await expectLater(
          client.send(IpcCommands.launch, {'serial': 'FAKESERIAL'}),
          throwsA(isA<IpcCommandFailed>()));
      // The failed start is followed by a snapshot that says so.
      await waitFor(() => mirroring.length >= 2, 'a snapshot after the failure');

      expect(mirroring, everyElement(isFalse));
      expect((await d.listDevices()).single['mirroring'], isFalse);
    });
  });

  group('Go Wireless and handoff for one phone', () {
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('condition not met in 20 s');
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }

    bool hasStage(List<IpcEvent> events, String stage) => events.any((e) =>
        (e.event == IpcEvents.wirelessStatus ||
            e.event == IpcEvents.handoffStatus) &&
        e.data['stage'] == stage);

    Future<(IpcClient, List<IpcEvent>)> connect(DaemonHarness d) async {
      final client = IpcClient();
      await client.connect(port: d.ipcPort);
      addTearDown(client.close);
      final events = <IpcEvent>[];
      client.events.listen(events.add);
      return (client, events);
    }

    test('a second request is turned away while the first is running',
        () async {
      // Regression for #19: only handoff was tracked, so a second Go Wireless
      // (or a handoff) for the same phone started alongside the first, sent
      // tcpip again and raced to launch.
      final d = await startDaemon();
      await d.waitForLog('[+] Pixel 7');
      final (client, events) = await connect(d);

      final first = await client
          .send(IpcCommands.goWireless, {'serial': 'FAKESERIAL'});
      expect(first.data['started'], isTrue);
      // Go Wireless now waits for the user to bring up a hotspot.
      await waitFor(() => hasStage(events, 'waitingForHotspot'));

      final again = await client
          .send(IpcCommands.goWireless, {'serial': 'FAKESERIAL'});
      expect(again.data['started'], isFalse);
      expect(again.data['reason'], contains('already in progress'));

      final handoff =
          await client.send(IpcCommands.handoff, {'serial': 'FAKESERIAL'});
      expect(handoff.data['started'], isFalse);
      expect(handoff.data['reason'], contains('Go Wireless is in progress'));

      // The turned-away requests are visible to a UI, and the running one was
      // not disturbed: it never reported a failure.
      await waitFor(() => hasStage(events, 'alreadyRunning'));
      expect(hasStage(events, 'failed'), isFalse);
      expect(d.isAlive, isTrue);
    });

    test('a finished operation releases the phone for the next request',
        () async {
      final d = await startDaemon();
      await d.waitForLog('[+] Pixel 7');
      final (client, events) = await connect(d);
      int failures() => events
          .where((e) =>
              e.event == IpcEvents.wirelessStatus &&
              e.data['stage'] == 'failed' &&
              e.data['serial'] == 'nope')
          .length;

      // An unknown serial fails at once, so the operation ends quickly.
      final first =
          await client.send(IpcCommands.goWireless, {'serial': 'nope'});
      expect(first.data['started'], isTrue);
      await waitFor(() => failures() == 1);

      final second =
          await client.send(IpcCommands.goWireless, {'serial': 'nope'});
      expect(second.data['started'], isTrue,
          reason: 'the first request finished, so the phone is free again');
      await waitFor(() => failures() == 2);
    });
  });

  group('device transport', () {
    // Serials of each shape, the mDNS and emulator ones as observed from real
    // adb (a Pixel on wireless debugging and a booted AVD, 2026-10-28).
    const usbSerial = 'FAKESERIAL';
    const mdnsSerial = 'adb-65261XEA33U4D0-HvLNB1._adb-tls-connect._tcp';
    const emulatorSerial = 'emulator-5554';
    const networkSerial = '192.168.43.1:5555';

    Future<DaemonHarness> startWithAllKinds() async {
      final d = await startDaemon();
      await d.waitForLog('[+] Pixel 7');
      adb.setDevices('$usbSerial\tdevice\n$emulatorSerial\tdevice\n'
          '$mdnsSerial\tdevice\n$networkSerial\tdevice\n');
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while ((await d.listDevices()).length < 4) {
        if (DateTime.now().isAfter(deadline)) fail('devices never all listed');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return d;
    }

    test('each device is reported with its transport', () async {
      final d = await startWithAllKinds();

      final transports = {
        for (final device in await d.listDevices())
          device['serial'] as String: device['transport'],
      };
      expect(transports, {
        usbSerial: 'usb',
        emulatorSerial: 'emulator',
        mdnsSerial: 'mdns',
        networkSerial: 'network',
      });
    });

    test('the log says how each device is connected', () async {
      // Regression for #28: an mDNS phone and an emulator were both logged as
      // "connected via USB".
      final d = await startWithAllKinds();

      await d.waitForLog('($emulatorSerial) connected via emulator');
      await d.waitForLog('($mdnsSerial) connected via wireless debugging');
      await d.waitForLog('($networkSerial) connected via wireless');
      expect(d.log.where((l) => l.contains('connected via USB')),
          hasLength(1),
          reason: 'only the real USB device');
    });

    test('Go Wireless and handoff are turned away for everything but USB, '
        'without sending anything to adb', () async {
      // Regression for #28: Go Wireless was accepted for an emulator (it
      // restarted the emulator's adbd and then tried to connect to the host's
      // LAN gateway) and for a phone already on wireless debugging.
      final d = await startWithAllKinds();
      final client = IpcClient();
      await client.connect(port: d.ipcPort);
      addTearDown(client.close);

      final expectedWords = {
        emulatorSerial: 'an emulator',
        mdnsSerial: 'wireless debugging',
        networkSerial: 'already on a wireless address',
      };
      for (final entry in expectedWords.entries) {
        for (final command in [IpcCommands.goWireless, IpcCommands.handoff]) {
          final result = await client.send(command, {'serial': entry.key});
          expect(result.data['started'], isFalse,
              reason: '$command for ${entry.key}');
          expect(result.data['reason'], contains('only for a phone connected '
              'by USB'));
          expect(result.data['reason'], contains(entry.value));
        }
      }
      expect(adb.tcpipRequests, 0,
          reason: 'nothing was sent to a device that cannot switch');
      expect(d.isAlive, isTrue);
    });

    test('Go Wireless is still accepted for a USB phone', () async {
      // The phone's Wi-Fi address is the listed network device, so Go
      // Wireless can finish instead of retrying until the daemon is killed.
      adb.setIpRoute('192.168.43.0/24 dev wlan0 proto kernel scope link '
          'src 192.168.43.1\n');
      final d = await startWithAllKinds();
      final client = IpcClient();
      await client.connect(port: d.ipcPort);
      addTearDown(client.close);
      final ended = client.events.firstWhere((e) =>
          e.event == IpcEvents.wirelessStatus &&
          e.data['serial'] == usbSerial &&
          (e.data['stage'] == 'connected' || e.data['stage'] == 'failed'));

      final result =
          await client.send(IpcCommands.goWireless, {'serial': usbSerial});

      expect(result.data['started'], isTrue);
      // Wait for the flow to end either way. Killing the daemon while it was
      // still talking to the fake adb reset the fake's sockets on Linux.
      await ended.timeout(const Duration(seconds: 30));
    });

    test('USB-only mode is refused for an emulator and for wireless debugging',
        () async {
      final d = await startWithAllKinds();
      final client = IpcClient();
      await client.connect(port: d.ipcPort);
      addTearDown(client.close);

      for (final serial in [emulatorSerial, mdnsSerial]) {
        await expectLater(
          client.send(IpcCommands.usbMode, {'serial': serial}),
          throwsA(isA<IpcCommandFailed>().having(
              (e) => e.message, 'message', contains('does not apply'))),
        );
      }
      expect(d.isAlive, isTrue);
    });
  });

  group('saved wireless address (#53)', () {
    const usbSerial = 'FAKESERIAL'; // what the fake answers for ro.serialno
    const mdnsSerial = 'adb-FAKESERIAL-HvLNB1._adb-tls-connect._tcp';
    const oldAddress = '10.0.0.5';
    const newAddress = '192.168.43.1';
    final saved = [
      {
        'usbSerial': usbSerial,
        'model': 'Pixel 7',
        'lastIp': oldAddress,
        'lastPort': 5555,
      },
    ];

    Future<void> waitForSavedIp(DaemonHarness d, String ip) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (d.savedWireless()[usbSerial]?['lastIp'] != ip) {
        if (DateTime.now().isAfter(deadline)) {
          fail('saved address never became $ip: ${d.savedWireless()}\n'
              '${d.log.join('\n')}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('a known phone ready at a new address updates the saved address',
        () async {
      final d = await startDaemon(savedWireless: saved);
      await d.waitForLog('[+] Pixel 7');
      adb.setDevices('$usbSerial\tdevice\n$newAddress:5555\tdevice\n');

      await waitForSavedIp(d, newAddress);
    });

    test('Wireless debugging for the same phone never overwrites the address',
        () async {
      final d = await startDaemon(savedWireless: saved);
      await d.waitForLog('[+] Pixel 7');
      adb.setDevices('$usbSerial\tdevice\n$mdnsSerial\tdevice\n');
      await d.waitForLog('($mdnsSerial) connected via wireless debugging');

      // Give a wrongly started update time to show up, then check.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(d.savedWireless()[usbSerial]!['lastIp'], oldAddress);
    });

    test('a different phone at a new address is not saved', () async {
      adb.setSerialNumber('SOMEONEELSE');
      final d = await startDaemon(savedWireless: saved);
      await d.waitForLog('[+] Pixel 7');
      adb.setDevices('$usbSerial\tdevice\n$newAddress:5555\tdevice\n');
      await d.waitForLog('($newAddress:5555) connected via wireless');

      await Future<void>.delayed(const Duration(seconds: 1));
      expect(d.savedWireless()[usbSerial]!['lastIp'], oldAddress);
    });
  });
}
