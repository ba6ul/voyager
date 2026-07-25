import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeAdbServer {
  FakeAdbServer._(this._server);

  final ServerSocket _server;
  final _trackClients = <Socket>[];
  String _devicesPayload = 'FAKESERIAL\tdevice\n';

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
      _okayWithPayload(socket, _devicesPayload);
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

  /// Updates what `host:devices` reports from now on, and pushes the same
  /// snapshot to any live `track-devices` subscribers, as if the device list
  /// had actually changed.
  void setDevices(String payload) {
    _devicesPayload = payload;
    pushTrackSnapshot(payload);
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
