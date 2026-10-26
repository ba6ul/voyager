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
  }) async {
    final d = await DaemonHarness.start(
      adbPort: adbPort ?? adb.port,
      autoLaunch: autoLaunch,
      adbPath: adbPath,
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
}
