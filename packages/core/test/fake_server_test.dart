import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('serialNumber reads ro.serialno over the transport', () async {
    expect(await client.serialNumber('FAKESERIAL'), 'FAKESERIAL');
  });

  test('serialNumber is null when the device reports none', () async {
    server.setSerialNumber('');
    expect(await client.serialNumber('FAKESERIAL'), isNull);
  });

  group('pair', () {
    test('a good code and address pairs the phone', () async {
      final result = await client.pair('192.168.1.8:37123', '123456');

      expect(result.outcome, PairOutcome.paired);
      expect(result.guid, 'adb-FAKESERIAL-abc123');
      expect(server.pairRequests.single.address, '192.168.1.8:37123');
      expect(server.pairRequests.single.code, '123456');
    });

    test('a rejected code is reported as a wrong code', () async {
      server.setPairReply('Failed: Wrong password or connection was dropped.');
      final result = await client.pair('192.168.1.8:37123', '000000');

      expect(result.outcome, PairOutcome.wrongCode);
      expect(result.message, isNot(contains('000000')));
    });

    test('an address nothing answers at is reported as unreachable', () async {
      server.setPairReply('Failed: Unable to start pairing client.');
      final result = await client.pair('192.168.1.8:37123', '123456');

      expect(result.outcome, PairOutcome.unreachable);
    });

    test('a phone that never answers times out as unreachable', () async {
      server.stallPairReplies(true);
      final result = await client.pair('192.168.1.8:37123', '123456',
          timeout: const Duration(milliseconds: 100));

      expect(result.outcome, PairOutcome.unreachable);
      server.stallPairReplies(false);
    });

    test('a bad address or code is refused before anything is sent', () async {
      for (final address in ['', 'host:1', '1.2.3:4', '300.1.1.1:5',
          '1.1.1.1:0', '1.1.1.1:70000', '1.1.1.1:5:7', '1.1.1.1:5 x']) {
        expect(() => client.pair(address, '123456'),
            throwsA(isA<ArgumentError>()),
            reason: address);
      }
      for (final code in ['', '12345', '1234567', 'abcdef', '12 456', '123:56']) {
        expect(() => client.pair('192.168.1.8:37123', code),
            throwsA(isA<ArgumentError>()),
            reason: code);
      }
      expect(server.pairRequests, isEmpty);
    });
  });

  test('FAIL responses surface as AdbServerException', () async {
    expect(
      () => client.shell('NOPE', 'id'),
      throwsA(isA<AdbServerException>()),
    );
  });

  test('a client that resets its connection mid-request fails no test',
      () async {
    // What a daemon killed at teardown looks like to the fake: the
    // connection is reset (RST), not closed. SO_LINGER on with a 0 s timeout
    // makes destroy() send RST. Before the fake caught this, the reset
    // surfaced as an uncaught SocketException in whichever test was running.
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    socket.setRawOption(_lingerZero());
    socket.add(ascii.encode('000chost:dev')); // a request cut short
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    socket.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The fake still serves the next client.
    expect(await client.serverVersion(), '0029');
  });
}

/// `SO_LINGER` = {on, 0 s}. `struct linger` is two u_shorts on Windows and
/// two ints elsewhere; the option name is 0x0080 on Windows and macOS, 13 on
/// Linux.
RawSocketOption _lingerZero() {
  final value = Platform.isWindows ? Uint8List(4) : Uint8List(8);
  final data = ByteData.sublistView(value);
  if (Platform.isWindows) {
    data.setUint16(0, 1, Endian.host);
  } else {
    data.setInt32(0, 1, Endian.host);
  }
  final name = Platform.isLinux ? 13 : 0x0080;
  return RawSocketOption(RawSocketOption.levelSocket, name, value);
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
