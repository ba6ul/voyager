@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
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
}
