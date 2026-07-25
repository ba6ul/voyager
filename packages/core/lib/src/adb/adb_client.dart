import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/adb_device.dart';
import 'adb_protocol.dart';
import 'byte_reader.dart';

/// Low-level TCP socket client implementing the Android Debug Bridge (ADB) wire protocol.
///
/// This class handles atomic and streaming communication barriers over target host interfaces 
/// (defaulting to loopback port 5037). By bypassing command-line process serialization and shell text 
/// parsing, it establishes connection pipelines to manage hardware states, execute remote scripts, 
/// and process asynchronous event snapshots natively.
///
/// Lifecycle & Session Paradigms:
/// 1. Short-lived Multiplexing: Ephemeral socket allocation cycles manage one-shot structural service execution before immediate resource disposal.
/// 2. Long-lived Hardware Tracking: Subscribes persistent, blocking streaming loops to server device change logs to handle dynamic plug-and-play triggers.
/// 3. Infrastructure Recovery: Intercepts connection exceptions natively, spawning system-level server instances on-demand when ports are unmapped.
class AdbClient {
  AdbClient({
    this.host = '127.0.0.1',
    this.port = 5037,
    this.adbPath = 'adb',
    this.connectTimeout = const Duration(seconds: 3),
  });

  final String host;
  final int port;

  /// Path to the bundled adb binary, used only to start the server when it
  /// is not already running.
  final String adbPath;

  final Duration connectTimeout;

  // ---------------------------------------------------------------------
  // Server lifecycle
  // ---------------------------------------------------------------------

  /// Makes sure the adb server is up, spawning `adb start-server` if needed.
  Future<void> ensureServerRunning() async {
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      await socket.close();
      socket.destroy();
    } on SocketException {
      final result = await Process.run(adbPath, ['start-server']);
      if (result.exitCode != 0) {
        throw AdbServerException(
          'could not start adb server: ${result.stderr}',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Host services
  // ---------------------------------------------------------------------

  /// Returns the adb server protocol version (a sanity-check ping).
  Future<String> serverVersion() async {
    final conn = await _open();
    try {
      await conn.request('host:version');
      return await conn.readHexPayloadString();
    } finally {
      await conn.close();
    }
  }

  /// One-shot device list.
  Future<List<AdbDevice>> devices() async {
    final conn = await _open();
    try {
      await conn.request('host:devices');
      final payload = await conn.readHexPayloadString();
      return AdbProtocol.parseDeviceList(payload);
    } finally {
      await conn.close();
    }
  }

  /// Streams a full device-list snapshot every time any device connects,
  /// disconnects, or changes state. This is the engine behind USB
  /// plug-and-play: no polling, events arrive the moment Windows sees the
  /// cable.
  ///
  /// The stream closes if the adb server dies; the daemon is expected to
  /// re-subscribe with backoff.
  Stream<List<AdbDevice>> trackDevices() {
    late StreamController<List<AdbDevice>> controller;
    _AdbConnection? conn;
    var cancelled = false;

    Future<void> run() async {
      try {
        conn = await _open();
        await conn!.request('host:track-devices');
        while (!cancelled) {
          final payload = await conn!.readHexPayloadString();
          controller.add(AdbProtocol.parseDeviceList(payload));
        }
      } catch (e, s) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(e, s);
        }
      } finally {
        await conn?.close();
        if (!controller.isClosed) await controller.close();
      }
    }

    controller = StreamController<List<AdbDevice>>(
      onListen: run,
      onCancel: () async {
        cancelled = true;
        await conn?.close();
      },
    );
    return controller.stream;
  }

  /// `adb connect <address>` for wireless devices. Returns the server's
  /// human-readable message. Note: adb replies OKAY even when the TCP
  /// connection fails, so callers should check [connectSucceeded] or verify
  /// the device shows up in [devices].
  Future<String> connectDevice(String hostAddress, [int devicePort = 5555]) async {
    final conn = await _open();
    try {
      await conn.request('host:connect:$hostAddress:$devicePort');
      return await conn.readHexPayloadString();
    } finally {
      await conn.close();
    }
  }

  static bool connectSucceeded(String message) =>
      message.contains('connected to') && !message.contains('failed');

  Future<String> disconnectDevice(String hostAddress, [int devicePort = 5555]) async {
    final conn = await _open();
    try {
      await conn.request('host:disconnect:$hostAddress:$devicePort');
      return await conn.readHexPayloadString();
    } finally {
      await conn.close();
    }
  }

  // ---------------------------------------------------------------------
  // Per-device services (via host:transport)
  // ---------------------------------------------------------------------

  /// Runs a shell command on [serial] and returns its combined output.
  Future<String> shell(String serial, String command) async {
    final conn = await _open();
    try {
      await conn.request('host:transport:$serial');
      await conn.request('shell:$command');
      return utf8.decode(await conn.readToEnd(), allowMalformed: true).trim();
    } finally {
      await conn.close();
    }
  }

  /// Human-friendly device name, e.g. `Pixel 7`.
  Future<String> model(String serial) =>
      shell(serial, 'getprop ro.product.model');

  /// Restarts adbd on the device in TCP mode. Requires a working (usually
  /// USB) transport. Survives unplugging, resets on phone reboot.
  Future<String> tcpip(String serial, [int devicePort = 5555]) async {
    final conn = await _open();
    try {
      await conn.request('host:transport:$serial');
      await conn.request('tcpip:$devicePort');
      return utf8.decode(await conn.readToEnd(), allowMalformed: true).trim();
    } finally {
      await conn.close();
    }
  }

  /// Back to USB-only mode (closes the network port 5555 for security).
  Future<String> usbMode(String serial) async {
    final conn = await _open();
    try {
      await conn.request('host:transport:$serial');
      await conn.request('usb:');
      return utf8.decode(await conn.readToEnd(), allowMalformed: true).trim();
    } finally {
      await conn.close();
    }
  }

  /// The phone's own WiFi IP (same-network case). Null when WiFi is off or
  /// the phone is acting as a hotspot; in hotspot mode connect to the PC's
  /// default gateway on the hotspot interface instead.
  Future<String?> wifiIp(String serial) async {
    final output = await shell(serial, 'ip route');
    return AdbProtocol.parseWlanIp(output);
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<_AdbConnection> _open() async {
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    return _AdbConnection(socket);
  }
}

class _AdbConnection {
  _AdbConnection(this._socket) : _reader = ByteReader(_socket);

  final Socket _socket;
  final ByteReader _reader;

  /// Sends a service request and consumes the OKAY/FAIL status.
  Future<void> request(String service) async {
    _socket.add(AdbProtocol.encodeRequest(service));
    await _socket.flush();
    final status = ascii.decode(await _reader.readBytes(4));
    if (status == AdbProtocol.statusOkay) return;
    if (status == AdbProtocol.statusFail) {
      final message = await readHexPayloadString();
      throw AdbServerException(message);
    }
    throw AdbProtocolException('unexpected status "$status"');
  }

  Future<String> readHexPayloadString() async {
    final length = AdbProtocol.parseHexLength(await _reader.readBytes(4));
    if (length == 0) return '';
    return utf8.decode(await _reader.readBytes(length), allowMalformed: true);
  }

  Future<List<int>> readToEnd() => _reader.readToEnd();

  Future<void> close() async {
    try {
      _socket.destroy();
    } catch (_) {}
    await _reader.cancel();
  }
}
