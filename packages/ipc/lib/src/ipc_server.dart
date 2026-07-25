import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'messages.dart';

/// Thrown by [IpcServer.start] when the port is already taken, which almost
/// always means another daemon instance is running. Callers should catch this
/// and exit cleanly instead of running a second device-tracking loop.
class DaemonAlreadyRunning implements Exception {
  final int port;
  DaemonAlreadyRunning(this.port);

  @override
  String toString() =>
      'Another daemon appears to be listening on 127.0.0.1:$port';
}

/// Loopback TCP server speaking the newline-delimited JSON protocol.
///
/// The daemon owns one instance. It routes incoming [IpcRequest]s to
/// [onCommand] and pushes [IpcEvent]s to every connected client via
/// [broadcast]. When a client connects, [snapshot] (if provided) is called
/// and its events are sent to that client only, so a freshly opened UI
/// immediately knows the current device list without asking.
class IpcServer {
  /// Handles one command and returns the result data. Throw (anything) to
  /// send a failure result; the exception's toString becomes the error text.
  final Future<Map<String, dynamic>> Function(IpcRequest request) onCommand;

  /// Events to send to a client right after it connects (state catch-up).
  final List<IpcEvent> Function()? snapshot;

  /// Optional logger for server-side diagnostics.
  final void Function(String message)? onLog;

  ServerSocket? _server;
  final Set<Socket> _clients = {};

  IpcServer({required this.onCommand, this.snapshot, this.onLog});

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;

  Future<void> start({int port = kDefaultIpcPort}) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw DaemonAlreadyRunning(port);
    }
    _log('IPC listening on 127.0.0.1:$port');
    _server!.listen(_handleClient, onError: (Object e) {
      _log('IPC accept error: $e');
    });
  }

  void _handleClient(Socket socket) {
    _clients.add(socket);
    _log('IPC client connected (${_clients.length} total)');

    // Catch-up: tell the new client the current state.
    final catchUp = snapshot?.call() ?? const [];
    for (final event in catchUp) {
      _send(socket, event.toJson());
    }

    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _handleLine(socket, line),
          onDone: () => _dropClient(socket),
          onError: (Object _) => _dropClient(socket),
          cancelOnError: true,
        );
  }

  Future<void> _handleLine(Socket socket, String line) async {
    final json = decodeLine(line);
    if (json == null) {
      _send(socket, IpcEvent.log('daemon: ignoring malformed line').toJson());
      return;
    }
    final request = IpcRequest.tryParse(json);
    if (request == null) {
      _send(socket, IpcEvent.log('daemon: not a command: $line').toJson());
      return;
    }
    IpcResult result;
    try {
      final data = await onCommand(request);
      result = IpcResult.success(request.id, data);
    } catch (e) {
      result = IpcResult.failure(request.id, e.toString());
    }
    _send(socket, result.toJson());
  }

  /// Sends an event to every connected client. Safe to call with zero
  /// clients; the daemon does not care whether a UI is watching.
  void broadcast(IpcEvent event) {
    final line = encodeLine(event.toJson());
    for (final socket in List.of(_clients)) {
      try {
        socket.write(line);
      } catch (_) {
        _dropClient(socket);
      }
    }
  }

  void _send(Socket socket, Map<String, dynamic> json) {
    try {
      socket.write(encodeLine(json));
    } catch (_) {
      _dropClient(socket);
    }
  }

  void _dropClient(Socket socket) {
    if (_clients.remove(socket)) {
      _log('IPC client disconnected (${_clients.length} left)');
    }
    socket.destroy();
  }

  Future<void> stop() async {
    for (final socket in List.of(_clients)) {
      socket.destroy();
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }

  void _log(String message) => onLog?.call(message);
}
