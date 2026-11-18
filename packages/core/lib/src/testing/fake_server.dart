import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeAdbServer {
  FakeAdbServer._(this._server);

  final ServerSocket _server;
  final _trackClients = <Socket>[];
  String _devicesPayload = 'FAKESERIAL\tdevice\n';
  bool _stallModelReplies = false;
  bool _stallTcpipReplies = false;
  int _tcpipRequests = 0;
  final _stalled = <Socket, void Function()>{};
  String _ipRouteOutput =
      '192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42\n';
  String _serialNumber = 'FAKESERIAL';
  String? _pairReply;
  bool _connectListsDevices = false;
  final _offlineConnects = <String>{};
  bool _stallPairReplies = false;

  int get port => _server.port;

  static Future<FakeAdbServer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeAdbServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  void _handle(Socket socket) async {
    // A client can vanish mid-request (a daemon process killed at test
    // teardown). On Linux that surfaces as ECONNRESET on this socket's reads
    // and writes. Nothing awaits this handler, so an uncaught error would
    // fail whichever test happens to be running; a fake has nothing to
    // report about a client that went away.
    socket.done.catchError((Object _) => socket);
    final buffer = <int>[];
    try {
      await for (final chunk in socket) {
        buffer.addAll(chunk);
        while (true) {
          if (buffer.length < 4) break;
          final length =
              int.parse(ascii.decode(buffer.sublist(0, 4)), radix: 16);
          if (buffer.length < 4 + length) break;
          final service = ascii.decode(buffer.sublist(4, 4 + length));
          buffer.removeRange(0, 4 + length);
          final keepOpen = _dispatch(socket, service);
          if (!keepOpen) return;
        }
      }
    } on SocketException {
      // The client went away; see above.
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
      if (_connectListsDevices && !_offlineConnects.contains(address)) {
        _devicesPayload = '$_devicesPayload$address\tdevice\n';
      }
      _okayWithPayload(socket, 'connected to $address');
      _end(socket);
      return false;
    }
    if (service.startsWith('host:pair:')) {
      // host:pair:<code>:<ip:port>
      final rest = service.substring('host:pair:'.length);
      final colon = rest.indexOf(':');
      pairRequests.add((code: rest.substring(0, colon), address: rest.substring(colon + 1)));
      final reply = _pairReply ??
          'Successfully paired to ${rest.substring(colon + 1)} '
              '[guid=adb-FAKESERIAL-abc123]';
      if (_stallPairReplies) {
        _stalled[socket] = () {
          _pairPayload(socket, reply);
          _end(socket);
        };
        return true;
      }
      _pairPayload(socket, reply);
      _end(socket);
      return false;
    }
    if (service.startsWith('host:transport:')) {
      final serial = service.substring('host:transport:'.length);
      final listed = _devicesPayload
          .split('\n')
          .any((line) => line.split('\t').first == serial);
      if (serial != 'FAKESERIAL' && !listed) {
        socket.add(ascii.encode('FAIL'));
        _hexPayload(socket, 'device \'$serial\' not found');
        _end(socket);
        return false;
      }
      socket.add(ascii.encode('OKAY'));
      return true; // next request on the same socket is the local service
    }
    if (service.startsWith('shell:')) {
      final command = service.substring('shell:'.length);
      if (_stallModelReplies && command == 'getprop ro.product.model') {
        // Accept the request and never answer, like a device whose adb
        // transport is busy or wedged.
        _stalled[socket] = () {
          socket.add(ascii.encode('OKAY'));
          socket.add(utf8.encode('Pixel 7\n'));
          _end(socket);
        };
        return true;
      }
      socket.add(ascii.encode('OKAY'));
      if (command == 'getprop ro.product.model') {
        socket.add(utf8.encode('Pixel 7\n'));
      } else if (command == 'getprop ro.serialno') {
        socket.add(utf8.encode('$_serialNumber\n'));
      } else if (command == 'ip route') {
        socket.add(utf8.encode(_ipRouteOutput));
      } else {
        socket.add(utf8.encode('ok\n'));
      }
      _end(socket);
      return false;
    }
    if (service.startsWith('tcpip:')) {
      _tcpipRequests++;
      if (_stallTcpipReplies) {
        _stalled[socket] = () {
          socket.add(ascii.encode('OKAY'));
          socket.add(utf8.encode('restarting in TCP mode port: 5555\n'));
          _end(socket);
        };
        return true;
      }
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

  /// While true, `getprop ro.product.model` (the model-name lookup) is not
  /// answered. Other requests are unaffected. Setting it back to false
  /// answers the requests that were held, as a slow device finally would.
  void stallModelReplies(bool stall) {
    _stallModelReplies = stall;
    if (!stall) _releaseStalled();
  }

  /// While true, `tcpip:` requests (the switch to TCP mode) are counted but
  /// not answered, like a phone whose adb transport is wedged. Setting it
  /// back to false answers the requests that were held, as a late
  /// completion would.
  void stallTcpipReplies(bool stall) {
    _stallTcpipReplies = stall;
    if (!stall) _releaseStalled();
  }

  /// How many `tcpip:` requests the server has received.
  int get tcpipRequests => _tcpipRequests;

  void _releaseStalled() {
    final held = _stalled.values.toList();
    _stalled.clear();
    for (final reply in held) {
      reply();
    }
  }

  /// Sets what `shell:ip route` returns from now on. An empty string models a
  /// phone with no WiFi address (WiFi off, or the phone is the hotspot).
  void setIpRoute(String output) => _ipRouteOutput = output;

  /// When true, a successful `host:connect` adds the address to the device
  /// list as `device`, like the real server (off by default).
  void connectListsDevices(bool value) => _connectListsDevices = value;

  /// `host:connect` to [address] says "connected" but the device never leaves
  /// the list as offline, like a port that is open but is not adb's.
  void connectStaysOffline(String address) => _offlineConnects.add(address);

  /// What `host:pair` answers from now on (null = a success message).
  void setPairReply(String? reply) => _pairReply = reply;

  /// While true, `host:pair` requests are counted but not answered, like a
  /// phone whose pairing dialog is closed.
  void stallPairReplies(bool stall) {
    _stallPairReplies = stall;
    if (!stall) _releaseStalled();
  }

  /// Every `host:pair` the server has received, oldest first.
  final pairRequests = <({String code, String address})>[];

  /// Sets what `shell:getprop ro.serialno` returns from now on (default
  /// `FAKESERIAL`). An empty string models a device that reports none.
  void setSerialNumber(String value) => _serialNumber = value;

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

  /// What the real adb server sends for `host:pair`: OKAY, then its own
  /// OKAY or FAIL status, then the message.
  void _pairPayload(Socket socket, String message) {
    socket.add(ascii.encode(
        message.toLowerCase().startsWith('successfully') ? 'OKAYOKAY' : 'OKAYFAIL'));
    _hexPayload(socket, message);
  }

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
    for (final client in _stalled.keys) {
      client.destroy();
    }
    await _server.close();
  }
}
