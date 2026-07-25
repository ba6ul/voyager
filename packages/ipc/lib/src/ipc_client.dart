import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'messages.dart';

/// Client side of the daemon protocol. The Flutter UI (and the probe tool)
/// use this; they never open raw sockets themselves.
///
/// Usage:
///   final client = IpcClient();
///   await client.connect();
///   client.events.listen((e) => ...);          // devices, wirelessStatus...
///   final r = await client.send(IpcCommands.launch, {'serial': serial});
class IpcClient {
  Socket? _socket;
  int _nextId = 0;
  final Map<String, Completer<IpcResult>> _pending = {};
  final StreamController<IpcEvent> _events = StreamController.broadcast();
  final Completer<void> _closed = Completer<void>();

  /// Broadcast stream of daemon events (device snapshots, wireless progress,
  /// scrcpy exits, log lines).
  Stream<IpcEvent> get events => _events.stream;

  /// Completes when the connection drops, however that happens. The UI can
  /// use this to show a "daemon not running" state and retry.
  Future<void> get onDisconnected => _closed.future;

  bool get isConnected => _socket != null;

  Future<void> connect({
    String host = '127.0.0.1',
    int port = kDefaultIpcPort,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    _socket = socket;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onDone: _handleDisconnect,
          onError: (Object _) => _handleDisconnect(),
          cancelOnError: true,
        );
  }

  /// Sends one command and completes with the daemon's result. Completes
  /// with an error if the daemon replies ok=false, the connection drops,
  /// or [timeout] passes with no reply.
  Future<IpcResult> send(
    String cmd, [
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('IpcClient is not connected');
    }
    final id = (_nextId++).toString();
    final completer = Completer<IpcResult>();
    _pending[id] = completer;
    socket.write(encodeLine(IpcRequest(id: id, cmd: cmd, args: args).toJson()));

    final result = await completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('No reply to "$cmd" within $timeout');
    });
    if (!result.ok) {
      throw IpcCommandFailed(cmd, result.error ?? 'unknown error');
    }
    return result;
  }

  void _handleLine(String line) {
    final json = decodeLine(line);
    if (json == null) return;

    final result = IpcResult.tryParse(json);
    if (result != null) {
      _pending.remove(result.id)?.complete(result);
      return;
    }
    final event = IpcEvent.tryParse(json);
    if (event != null && !_events.isClosed) {
      _events.add(event);
    }
  }

  void _handleDisconnect() {
    _socket = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Connection to daemon lost'));
      }
    }
    _pending.clear();
    if (!_closed.isCompleted) _closed.complete();
    _events.close();
  }

  Future<void> close() async {
    _socket?.destroy();
    _handleDisconnect();
  }
}

/// Thrown by [IpcClient.send] when the daemon reports a command failure.
class IpcCommandFailed implements Exception {
  final String cmd;
  final String message;
  IpcCommandFailed(this.cmd, this.message);

  @override
  String toString() => 'Command "$cmd" failed: $message';
}
