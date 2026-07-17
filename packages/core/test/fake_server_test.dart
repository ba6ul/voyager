import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

/// A tiny in-process stand-in for the real adb server, speaking just enough
/// of the smart-socket protocol to exercise AdbClient end to end.
class FakeAdbServer {
  FakeAdbServer._(this._server);

  final ServerSocket _server;
  final _trackClients = <Socket>[];

  int get port => _server.port;

  static Future<FakeAdbServer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeAdbServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  void _handle(Socket socket) async {
    final buffer = <int>[];
    await for (final chunk in socket) {
      buffer.addAll(chunk);
      while (true) {
        if (buffer.length < 4) break;
        final length = int.parse(ascii.decode(buffer.sublist(0, 4)), radix: 16);
        if (buffer.length < 4 + length) break;
        final service = ascii.decode(buffer.sublist(4, 4 + length));
        buffer.removeRange(0, 4 + length);
        final keepOpen = _dispatch(socket, service);
        if (!keepOpen) return;
      }
    }
  }

  /// Flush pending writes, then close gracefully. `destroy()` on Windows can
  /// drop unflushed bytes, which made the client see EOF before the payload.
  void _end(Socket socket) {
    socket.flush().then((_) => socket.close()).catchError((_) {});
  }

  bool _dispatch(Socket socket, String service) {
    if (service == 'host:version') {
      _okayWithPayload(socket, '0029');
      _end(socket);
      return false;
    }
    if (service == 'host:devices') {
      _okayWithPayload(socket, 'FAKESERIAL\tdevice\n');
      _end(socket);
      return false;
    }
    if (service == 'host:track-devices') {
      socket.add(ascii.encode('OKAY'));
      _trackClients.add(socket);
      _pushSnapshot(socket, 'FAKESERIAL\tdevice\n');
      return true;
    }
    if (service.startsWith('host:connect:')) {
      final address = service.substring('host:connect:'.length);
      _okayWithPayload(socket, 'connected to $address');
      _end(socket);
      return false;
    }
    if (service.startsWith('host:transport:')) {
      final serial = service.substring('host:transport:'.length);
      if (serial != 'FAKESERIAL') {
        socket.add(ascii.encode('FAIL'));
        _hexPayload(socket, 'device \'$serial\' not found');
        _end(socket);
        return false;
      }
      socket.add(ascii.encode('OKAY'));
      return true; // next request on the same socket is the local service
    }
    if (service.startsWith('shell:')) {
      socket.add(ascii.encode('OKAY'));
      final command = service.substring('shell:'.length);
      if (command == 'getprop ro.product.model') {
        socket.add(utf8.encode('Pixel 7\n'));
      } else if (command == 'ip route') {
        socket.add(
          utf8.encode(
            '192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42\n',
          ),
        );
      } else {
        socket.add(utf8.encode('ok\n'));
      }
      _end(socket);
      return false;
    }
    if (service.startsWith('tcpip:')) {
      socket.add(ascii.encode('OKAY'));
      socket.add(utf8.encode('restarting in TCP mode port: 5555\n'));
      _end(socket);
      return false;
    }
    // Unknown service.
    final message = 'unknown service: $service';
    socket.add(ascii.encode('FAIL'));
    _hexPayload(socket, message);
    _end(socket);
    return false;
  }

  void pushTrackSnapshot(String payload) {
    for (final client in List.of(_trackClients)) {
      _pushSnapshot(client, payload);
    }
  }

  void _pushSnapshot(Socket socket, String payload) =>
      _hexPayload(socket, payload);

  void _okayWithPayload(Socket socket, String payload) {
    socket.add(ascii.encode('OKAY'));
    _hexPayload(socket, payload);
  }

  void _hexPayload(Socket socket, String payload) {
    final bytes = utf8.encode(payload);
    socket.add(ascii.encode(bytes.length.toRadixString(16).padLeft(4, '0')));
    socket.add(bytes);
  }

  Future<void> close() async {
    for (final client in _trackClients) {
      client.destroy();
    }
    await _server.close();
  }
}

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
