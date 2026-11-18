import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/wireless_debugging_pairer.dart';
import 'package:test/test.dart';

void main() {
  late FakeAdbServer adb;
  late AdbClient client;
  late List<String> stages;
  late List<String?> details;

  setUp(() async {
    adb = await FakeAdbServer.start();
    adb.connectListsDevices(true);
    client = AdbClient(port: adb.port);
    stages = [];
    details = [];
  });

  tearDown(() => adb.close());

  void onStatus(String stage, [String? detail]) {
    stages.add(stage);
    details.add(detail);
  }

  WirelessDebuggingPairer pairer({PortScanner? scan}) =>
      WirelessDebuggingPairer(
        client: client,
        scanPorts: scan ?? (host, from, to, skip) async => [],
        autoConnectWait: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
        scanWindow: const Duration(milliseconds: 150),
        scanRetryInterval: const Duration(milliseconds: 20),
        readyWait: const Duration(milliseconds: 100),
      );

  test('a wrong code ends at wrongCode and never searches', () async {
    adb.setPairReply('Failed: Wrong password or connection was dropped.');

    await pairer().pair('192.168.1.8:37123', '000000', onStatus: onStatus);

    expect(stages, ['pairing', 'wrongCode']);
    expect(details.join(' '), isNot(contains('000000')));
  });

  test('an address nothing answers at ends at unreachable', () async {
    adb.setPairReply('Failed: Unable to start pairing client.');

    await pairer().pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(stages, ['pairing', 'unreachable']);
  });

  test('adb connecting by itself after pairing is enough', () async {
    adb.setDevices(
        'adb-FAKESERIAL-abc123._adb-tls-connect._tcp\tdevice\n');
    var scanned = false;

    await pairer(scan: (h, f, t, s) async {
      scanned = true;
      return [];
    }).pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(stages, ['pairing', 'searching', 'connected']);
    expect(details.last, 'adb-FAKESERIAL-abc123._adb-tls-connect._tcp');
    expect(scanned, isFalse);
  });

  test('a phone already connected as ip:port counts, with no scan', () async {
    adb.setDevices('192.168.1.8:35253\tdevice\n');
    var scanned = false;

    await pairer(scan: (h, f, t, s) async {
      scanned = true;
      return [];
    }).pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(stages, ['pairing', 'searching', 'connected']);
    expect(details.last, '192.168.1.8:35253');
    expect(scanned, isFalse);
  });

  test('otherwise the host is scanned and the open port is connected',
      () async {
    String? scannedHost;
    Set<int>? skipped;
    String? savedIdentity;

    await pairer(scan: (host, from, to, skip) async {
      scannedHost = host;
      skipped = skip;
      return [40001];
    }).pair('192.168.1.8:37123', '123456',
        onStatus: onStatus,
        onConnected: (identity, serial) => savedIdentity = identity);

    expect(stages, ['pairing', 'searching', 'connected']);
    expect(details.last, '192.168.1.8:40001');
    expect(scannedHost, '192.168.1.8');
    expect(skipped, {37123}, reason: 'the pairing port is not a connect port');
    expect(savedIdentity, 'FAKESERIAL');
  });

  test('a port that stays offline is skipped and disconnected', () async {
    adb.connectStaysOffline('192.168.1.8:40001');

    await pairer(scan: (h, f, t, s) async => [40001, 40002])
        .pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(stages.last, 'connected');
    expect(details.last, '192.168.1.8:40002');
  });

  test('the scan is retried until the real port shows up', () async {
    var round = 0;

    await pairer(scan: (h, f, t, s) async => ++round < 3 ? [] : [40001])
        .pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(round, 3);
    expect(details.last, '192.168.1.8:40001');
  });

  test('paired but no connect port found ends at pairedOnly', () async {
    await pairer().pair('192.168.1.8:37123', '123456', onStatus: onStatus);

    expect(stages, ['pairing', 'searching', 'pairedOnly']);
  });

  test('a second pairing while one runs is turned away', () async {
    adb.stallPairReplies(true);
    final p = pairer();
    final first = p.pair('192.168.1.8:37123', '123456', onStatus: onStatus);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.busy, isTrue);

    final second = <String>[];
    await p.pair('192.168.1.8:37124', '654321',
        onStatus: (stage, [detail]) => second.add(stage));
    expect(second, ['failed']);

    adb.stallPairReplies(false);
    await first;
    expect(p.busy, isFalse);
  });

  test('scanOpenPorts finds a listening port and honours the skip set',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final port = server.port;

    expect(await scanOpenPorts('127.0.0.1', port, port, {}), [port]);
    expect(await scanOpenPorts('127.0.0.1', port, port, {port}), isEmpty);
  });
}
