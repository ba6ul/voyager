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
}
