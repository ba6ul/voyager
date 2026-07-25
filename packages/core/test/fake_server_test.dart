import 'dart:async';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

/// A tiny in-process stand-in for the real adb server, speaking just enough
/// of the smart-socket protocol to exercise AdbClient end to end.

void main() {
  late FakeAdbServer server;
  late AdbClient client;

  setUp(() async {
    server = await FakeAdbServer.start();
    client = AdbClient(port: server.port);
  });

  tearDown(() => server.close());

  test('serverVersion round-trips', () async {
    expect(await client.serverVersion(), '0029');
  });

  test('devices returns parsed list', () async {
    final devices = await client.devices();
    expect(devices.single.serial, 'FAKESERIAL');
    expect(devices.single.isReady, isTrue);
  });

  test('trackDevices streams snapshots as they change', () async {
    final snapshots = <List<AdbDevice>>[];
    final sub = client.trackDevices().listen(snapshots.add);

    // Initial snapshot arrives on subscribe.
    await _eventually(() => snapshots.length == 1);
    expect(snapshots[0].single.serial, 'FAKESERIAL');

    // Device unplugged.
    server.pushTrackSnapshot('');
    await _eventually(() => snapshots.length == 2);
    expect(snapshots[1], isEmpty);

    // Device replugged, unauthorized first.
    server.pushTrackSnapshot('FAKESERIAL\tunauthorized\n');
    await _eventually(() => snapshots.length == 3);
    expect(snapshots[2].single.state, AdbDeviceState.unauthorized);

    await sub.cancel();
  });

  test('shell runs through transport and reads to EOF', () async {
    expect(await client.model('FAKESERIAL'), 'Pixel 7');
  });

  test('wifiIp parses ip route through the full stack', () async {
    expect(await client.wifiIp('FAKESERIAL'), '192.168.1.42');
  });

  test('tcpip returns adbd restart message', () async {
    final message = await client.tcpip('FAKESERIAL');
    expect(message, contains('TCP mode'));
  });

  test('connectDevice returns server message', () async {
    final message = await client.connectDevice('192.168.43.1');
    expect(AdbClient.connectSucceeded(message), isTrue);
  });

  test('FAIL responses surface as AdbServerException', () async {
    expect(
      () => client.shell('NOPE', 'id'),
      throwsA(isA<AdbServerException>()),
    );
  });
}

Future<void> _eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within 3s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
