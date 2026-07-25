import 'dart:convert';

/// Default loopback port the daemon listens on. Overridable via config.json.
const int kDefaultIpcPort = 38765;

/// Command names understood by the daemon. Using constants instead of raw
/// strings keeps daemon and UI in sync and makes typos a compile-time grep.
abstract final class IpcCommands {
  static const listDevices = 'listDevices';
  static const launch = 'launch'; // args: {serial}
  static const stop = 'stop'; // args: {serial}
  static const stopAll = 'stopAll';
  static const goWireless = 'goWireless'; // args: {serial}
  static const handoff = 'handoff'; // args: {serial}
  static const usbMode = 'usbMode'; // args: {serial}
  static const retryReconnect = 'retryReconnect'; // args: {serial} (== cached usbSerial)
  static const getConfig = 'getConfig';
  static const setConfig = 'setConfig'; // args: {config: {...}}
  static const quit = 'quit';
}

/// Event names the daemon broadcasts.
abstract final class IpcEvents {
  /// Full device snapshot. data: {devices: [{serial, state, model?, mirroring}]}
  static const devices = 'devices';

  /// A device just became ready. data: {serial, model?}
  static const deviceReady = 'deviceReady';

  /// A device disappeared. data: {serial}
  static const deviceGone = 'deviceGone';

  /// A scrcpy window closed. data: {serial, exitCode}
  static const scrcpyExited = 'scrcpyExited';

  /// Progress of the wireless flow. data: {serial, stage, detail?}
  /// Stages: readingWifiIp, tcpipEnabled, waitingForHotspot, connecting,
  ///         connected (detail = network serial), failed (detail = reason)
  static const wirelessStatus = 'wirelessStatus';

  /// Progress of an in-flight handoff (USB -> wireless). data: {serial, stage, detail?}
  /// Stages: readingWifiIp, tcpipEnabled, connecting, launchingWireless,
  ///         closingUsb, complete (detail = network serial), failed (detail = reason)
  static const handoffStatus = 'handoffStatus';

  /// Free-form log line for the UI console. data: {message}
  static const log = 'log';

  /// Devices that have gone wireless before, whether or not they're
  /// currently reachable. data: {devices: [{usbSerial, model, lastIp, lastPort}]}
  static const knownDevices = 'knownDevices';
}

/// A command sent from a client to the daemon.
class IpcRequest {
  final String id;
  final String cmd;
  final Map<String, dynamic> args;

  const IpcRequest({required this.id, required this.cmd, this.args = const {}});

  static IpcRequest? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'cmd') return null;
    final id = json['id'];
    final cmd = json['cmd'];
    if (id is! String || cmd is! String) return null;
    final rawArgs = json['args'];
    return IpcRequest(
      id: id,
      cmd: cmd,
      args: rawArgs is Map<String, dynamic> ? rawArgs : const {},
    );
  }

  Map<String, dynamic> toJson() =>
      {'type': 'cmd', 'id': id, 'cmd': cmd, if (args.isNotEmpty) 'args': args};
}

/// The daemon's reply to a specific [IpcRequest].
class IpcResult {
  final String id;
  final bool ok;
  final Map<String, dynamic> data;
  final String? error;

  const IpcResult.success(this.id, [this.data = const {}])
      : ok = true,
        error = null;

  const IpcResult.failure(this.id, String this.error)
      : ok = false,
        data = const {};

  static IpcResult? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'result') return null;
    final id = json['id'];
    if (id is! String) return null;
    if (json['ok'] == true) {
      final rawData = json['data'];
      return IpcResult.success(
        id,
        rawData is Map<String, dynamic> ? rawData : const {},
      );
    }
    return IpcResult.failure(id, json['error']?.toString() ?? 'unknown error');
  }

  Map<String, dynamic> toJson() => {
        'type': 'result',
        'id': id,
        'ok': ok,
        if (ok) 'data': data,
        if (!ok) 'error': error,
      };
}

/// An unsolicited broadcast from the daemon.
class IpcEvent {
  final String event;
  final Map<String, dynamic> data;

  const IpcEvent(this.event, [this.data = const {}]);

  static IpcEvent? tryParse(Map<String, dynamic> json) {
    if (json['type'] != 'event') return null;
    final event = json['event'];
    if (event is! String) return null;
    final rawData = json['data'];
    return IpcEvent(
      event,
      rawData is Map<String, dynamic> ? rawData : const {},
    );
  }

  Map<String, dynamic> toJson() =>
      {'type': 'event', 'event': event, 'data': data};

  // Convenience constructors so daemon code reads cleanly.

  static IpcEvent devices(List<Map<String, dynamic>> devices) =>
      IpcEvent(IpcEvents.devices, {'devices': devices});

  static IpcEvent deviceReady(String serial, {String? model}) => IpcEvent(
      IpcEvents.deviceReady,
      {'serial': serial, if (model != null) 'model': model});

  static IpcEvent deviceGone(String serial) =>
      IpcEvent(IpcEvents.deviceGone, {'serial': serial});

  static IpcEvent scrcpyExited(String serial, int exitCode) => IpcEvent(
      IpcEvents.scrcpyExited, {'serial': serial, 'exitCode': exitCode});

  static IpcEvent wirelessStatus(String serial, String stage,
          [String? detail]) =>
      IpcEvent(IpcEvents.wirelessStatus, {
        'serial': serial,
        'stage': stage,
        if (detail != null) 'detail': detail,
      });

  static IpcEvent handoffStatus(String serial, String stage,
          [String? detail]) =>
      IpcEvent(IpcEvents.handoffStatus, {
        'serial': serial,
        'stage': stage,
        if (detail != null) 'detail': detail,
      });

  static IpcEvent log(String message) =>
      IpcEvent(IpcEvents.log, {'message': message});

  static IpcEvent knownDevices(List<Map<String, dynamic>> devices) =>
      IpcEvent(IpcEvents.knownDevices, {'devices': devices});
}

/// Encodes any message map as one wire line (JSON + newline).
String encodeLine(Map<String, dynamic> json) => '${jsonEncode(json)}\n';

/// Decodes one wire line into a JSON map, or null if malformed.
Map<String, dynamic>? decodeLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
