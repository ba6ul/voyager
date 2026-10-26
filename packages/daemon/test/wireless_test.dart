import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/wireless.dart';
import 'package:test/test.dart';

// Layout recorded from `route print -4` on Windows 11 (addresses are private
// LAN addresses). Two default routes through the same gateway, one per
// interface, plus rows whose gateway is `On-link`.
const _routePrintTwoInterfaces = '''
===========================================================================
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1      192.168.1.9     55
          0.0.0.0          0.0.0.0      192.168.1.1      192.168.1.4     50
        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
      192.168.1.0    255.255.255.0         On-link       192.168.1.9    311
  255.255.255.255  255.255.255.255         On-link       192.168.1.9    311
===========================================================================
Persistent Routes:
  None
''';

const _routePrintHotspotAndLan = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1      192.168.1.4     50
          0.0.0.0          0.0.0.0     192.168.43.1    192.168.43.77     25
      192.168.43.0    255.255.255.0         On-link    192.168.43.77    281
''';

// Same layout with German column headings: only the numeric rows are matched.
const _routePrintGerman = '''
IPv4-Routentabelle
===========================================================================
Aktive Routen:
Netzwerkziel    Netzwerkmaske    Gateway    Schnittstelle    Metrik
          0.0.0.0          0.0.0.0     10.0.0.1      10.0.0.20     35
''';

const _routePrintNoDefault = '''
IPv4 Route Table
===========================================================================
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
        127.0.0.0        255.0.0.0         On-link         127.0.0.1    331
      192.168.1.0    255.255.255.0         On-link       192.168.1.9    311
''';

const _routePrintDefaultOnLink = '''
Active Routes:
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0         On-link       192.168.1.9     55
''';

void main() {
  group('WirelessManager.parseDefaultGateways', () {
    test('reports a gateway shared by several interfaces once', () {
      expect(WirelessManager.parseDefaultGateways(_routePrintTwoInterfaces),
          {'192.168.1.1'});
    });

    test('reports every distinct default gateway', () {
      expect(WirelessManager.parseDefaultGateways(_routePrintHotspotAndLan),
          {'192.168.1.1', '192.168.43.1'});
    });

    test('does not depend on the language of the headings', () {
      expect(
          WirelessManager.parseDefaultGateways(_routePrintGerman), {'10.0.0.1'});
    });

    test('returns nothing without a default route', () {
      expect(
          WirelessManager.parseDefaultGateways(_routePrintNoDefault), isEmpty);
    });

    test('ignores a default route whose gateway is On-link', () {
      expect(WirelessManager.parseDefaultGateways(_routePrintDefaultOnLink),
          isEmpty);
    });

    test('returns nothing for empty output', () {
      expect(WirelessManager.parseDefaultGateways(''), isEmpty);
    });
  });

  group('WirelessManager.goWireless with an injected gateway provider', () {
    late FakeAdbServer server;
    late AdbClient client;

    setUp(() async {
      server = await FakeAdbServer.start();
      client = AdbClient(port: server.port);
    });

    tearDown(() => server.close());

    test('connects through the hotspot gateway and reports the stages',
        () async {
      server.setIpRoute('');
      server.setDevices('FAKESERIAL\tdevice\n192.168.43.1:5555\tdevice\n');
      final stages = <String>[];

      final result = await WirelessManager(
        client,
        gateways: () async => {'192.168.43.1'},
      ).goWireless(
        'FAKESERIAL',
        timeout: const Duration(seconds: 5),
        onStatus: (stage, [detail]) => stages.add(stage),
      );

      expect(result, '192.168.43.1:5555');
      expect(stages, [
        'readingWifiIp',
        'tcpipEnabled',
        'waitingForHotspot',
        'connecting',
        'connected',
      ]);
    });

    test('gives up and reports failure when no gateway ever answers',
        () async {
      server.setIpRoute('');
      final stages = <String>[];

      final result = await WirelessManager(
        client,
        gateways: () async => <String>{},
      ).goWireless(
        'FAKESERIAL',
        timeout: const Duration(seconds: 1),
        onStatus: (stage, [detail]) => stages.add(stage),
      );

      expect(result, isNull);
      expect(stages.last, 'failed');
    });

    test('an unknown serial reports a failure instead of throwing', () async {
      // Regression for #14: this used to throw AdbServerException out of
      // goWireless, and because the daemon runs the flow fire-and-forget, the
      // exception ended the whole process.
      final statuses = <String>[];

      final result = await WirelessManager(
        client,
        gateways: () async => <String>{},
      ).goWireless(
        'nope',
        timeout: const Duration(seconds: 1),
        onStatus: (stage, [detail]) => statuses.add('$stage:${detail ?? ''}'),
      );

      expect(result, isNull);
      expect(statuses.last, startsWith('failed:tcpip failed'));
      expect(statuses.last, contains("device 'nope' not found"));
      expect(statuses, isNot(contains('tcpipEnabled:')));
      expect(statuses, isNot(contains('waitingForHotspot:')));
    });

    test('an unreachable adb server reports a failure instead of throwing',
        () async {
      final deadClient = AdbClient(port: 1);
      final statuses = <String>[];

      final result = await WirelessManager(
        deadClient,
        gateways: () async => <String>{},
      ).goWireless(
        'FAKESERIAL',
        timeout: const Duration(seconds: 1),
        onStatus: (stage, [detail]) => statuses.add(stage),
      );

      expect(result, isNull);
      expect(statuses.last, 'failed');
    });
  });

  group('goWireless when the phone stops answering tcpip', () {
    late FakeAdbServer server;
    late AdbClient client;

    setUp(() async {
      server = await FakeAdbServer.start();
      client = AdbClient(port: server.port);
      server.setIpRoute('');
    });

    tearDown(() => server.close());

    WirelessManager manager({Duration settleTimeout = const Duration(seconds: 2)}) =>
        WirelessManager(
          client,
          gateways: () async => {'192.168.43.1'},
          tcpipTimeout: const Duration(milliseconds: 200),
          settleTimeout: settleTimeout,
          settlePollInterval: const Duration(milliseconds: 20),
        );

    Future<(String?, List<String>)> run(WirelessManager m,
        {Duration timeout = const Duration(seconds: 5)}) async {
      final statuses = <String>[];
      final result = await m.goWireless(
        'FAKESERIAL',
        timeout: timeout,
        onStatus: (stage, [detail]) => statuses.add('$stage:${detail ?? ''}'),
      );
      return (result, statuses);
    }

    test('fails explicitly within the timeout instead of hanging', () async {
      // Regression for #45: tcpip had no timeout in goWireless, so a phone
      // that stopped answering left the flow waiting forever.
      server.stallTcpipReplies(true);
      final watch = Stopwatch()..start();

      final (result, statuses) = await run(manager());

      expect(result, isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(statuses.last, startsWith('failed:the phone did not answer'));
      expect(statuses.last, contains('may still switch'));
      expect(statuses.last, contains('USB mirror was left as it is'));
      // A timeout is not treated as success: the flow never advanced.
      expect(statuses.any((s) => s.startsWith('tcpipEnabled')), isFalse);
      expect(statuses.any((s) => s.startsWith('waitingForHotspot')), isFalse);
      expect(server.tcpipRequests, 1);
    });

    test('a retry after a late completion goes ahead once the phone is ready',
        () async {
      final m = manager();
      server.stallTcpipReplies(true);
      final (first, _) = await run(m);
      expect(first, isNull);

      // The phone answers the first request after all (late completion), and
      // is back and ready with its hotspot address reachable.
      server.stallTcpipReplies(false);
      server.setDevices('FAKESERIAL\tdevice\n192.168.43.1:5555\tdevice\n');

      final (second, statuses) = await run(m);

      expect(second, '192.168.43.1:5555');
      expect(statuses.last, startsWith('connected'));
      expect(server.tcpipRequests, 2);
    });

    test('a retry waits while the phone is still restarting', () async {
      final m = manager();
      server.stallTcpipReplies(true);
      await run(m);
      server.stallTcpipReplies(false);
      // adbd is restarting: the phone is listed but not ready.
      server.setDevices('FAKESERIAL\toffline\n');

      final retry = run(m);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.tcpipRequests, 1,
          reason: 'nothing new is sent to a phone that is not ready');

      server.setDevices('FAKESERIAL\tdevice\n192.168.43.1:5555\tdevice\n');
      final (result, _) = await retry;

      expect(result, '192.168.43.1:5555');
      expect(server.tcpipRequests, 2);
    });

    test('a retry fails without sending anything if the phone never comes back',
        () async {
      final m = manager(settleTimeout: const Duration(milliseconds: 300));
      server.stallTcpipReplies(true);
      await run(m);
      server.stallTcpipReplies(false);
      server.setDevices('');

      final (result, statuses) = await run(m);

      expect(result, isNull);
      expect(statuses.last, startsWith('failed:the phone has not come back'));
      expect(server.tcpipRequests, 1);
    });

    test('settle is immediate when no attempt is outstanding', () async {
      final m = manager();
      server.setDevices('');

      expect(await m.settle('FAKESERIAL'), isTrue);
    });

    test('a tcpip that fails outright does not leave the serial unsettled',
        () async {
      // An unknown serial fails at once; that is a definite answer, not an
      // uncertain one, so the next attempt is not held up.
      final m = manager();
      await m.goWireless('nope', timeout: const Duration(seconds: 1));

      expect(await m.settle('nope'), isTrue);
    });

    test('a retry says it is waiting for the phone before doing anything',
        () async {
      final m = manager();
      server.stallTcpipReplies(true);
      await run(m);
      server.stallTcpipReplies(false);
      server.setDevices('FAKESERIAL\toffline\n');
      final statuses = <String>[];

      final retry = m.goWireless(
        'FAKESERIAL',
        timeout: const Duration(seconds: 5),
        onStatus: (stage, [detail]) => statuses.add(stage),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(statuses, ['waitingForPhone'],
          reason: 'the wait is visible while it lasts, before any other step');

      server.setDevices('FAKESERIAL\tdevice\n192.168.43.1:5555\tdevice\n');
      await retry;

      expect(statuses.take(2), ['waitingForPhone', 'readingWifiIp']);
    });

    test('settle reports nothing when no request is outstanding', () async {
      final statuses = <String>[];

      final ok = await manager().settle('FAKESERIAL',
          onStatus: (stage, [detail]) => statuses.add(stage));

      expect(ok, isTrue);
      expect(statuses, isEmpty);
    });

    test('markUncertain makes the next settle wait for a ready phone',
        () async {
      final m = manager(settleTimeout: const Duration(milliseconds: 300));
      m.markUncertain('FAKESERIAL');
      server.setDevices('');
      expect(await m.settle('FAKESERIAL'), isFalse);

      server.setDevices('FAKESERIAL\tdevice\n');
      expect(await m.settle('FAKESERIAL'), isTrue);
      // Once settled, the mark is gone.
      server.setDevices('');
      expect(await m.settle('FAKESERIAL'), isTrue);
    });
  });
}
