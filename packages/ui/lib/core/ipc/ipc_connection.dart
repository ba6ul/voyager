import 'dart:async';

import 'package:scrcpy_ipc/scrcpy_ipc.dart';

/// Keeps a connection to the daemon alive across restarts on either side.
///
/// The daemon may not be running yet when the UI starts (it's launched
/// separately), and either side can disconnect at any time, so this retries
/// on a fixed interval rather than connecting once and giving up.
class IpcConnection {
  IpcConnection({
    this.host = '127.0.0.1',
    this.port = kDefaultIpcPort,
    this.retryInterval = const Duration(seconds: 2),
  });

  final String host;
  final int port;
  final Duration retryInterval;

  IpcClient? _client;
  bool _started = false;
  bool _disposed = false;

  final _connectedController = StreamController<bool>.broadcast();
  final _eventsController = StreamController<IpcEvent>.broadcast();

  /// Whether the daemon is currently reachable.
  Stream<bool> get connected => _connectedController.stream;

  /// Every event the daemon broadcasts, while connected.
  Stream<IpcEvent> get events => _eventsController.stream;

  /// Begins the connect-retry loop. Safe to call more than once; only the
  /// first call has any effect.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    unawaited(_connectLoop());
  }

  Future<void> _connectLoop() async {
    while (!_disposed) {
      final client = IpcClient();
      try {
        await client.connect(host: host, port: port);
        _client = client;
        if (!_connectedController.isClosed) _connectedController.add(true);
        final sub = client.events.listen((event) {
          if (!_eventsController.isClosed) _eventsController.add(event);
        });
        await client.onDisconnected;
        await sub.cancel();
      } catch (_) {
        // Daemon not up yet, or the connection attempt itself failed.
      }
      _client = null;
      if (_disposed) return;
      if (!_connectedController.isClosed) _connectedController.add(false);
      await Future<void>.delayed(retryInterval);
    }
  }

  /// Sends a command to the daemon. Throws [StateError] if not currently
  /// connected — callers should surface that as a "daemon unreachable" state
  /// rather than retrying the send themselves.
  Future<IpcResult> send(String cmd, [Map<String, dynamic> args = const {}]) {
    final client = _client;
    if (client == null) {
      throw StateError('not connected to the daemon');
    }
    return client.send(cmd, args);
  }

  void dispose() {
    _disposed = true;
    _client?.close();
    _connectedController.close();
    _eventsController.close();
  }
}
