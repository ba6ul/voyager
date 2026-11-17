import 'dart:convert';
import 'dart:typed_data';

import '../models/adb_device.dart';

/// Pure serialization and text parsing protocol utilities for the ADB wire interface.
///
/// This class functions as a stateless translation barrier, implementing framing 
/// constraints for the ADB smart-socket architecture. It enforces message boundary formatting 
/// rules via 16-bit hex-length prefixes, decodes line-oriented hardware snapshots, and isolates 
/// device interface targets from text-based subshell execution streams.
///
/// Structural Serialization Contracts:
/// 1. Protocol Framing: Encodes text directives into hex-prefixed binary arrays while verifying strict length constraints.
/// 2. Stream De-serialization: Extracts explicit sizing primitives from inbound wire packets to drive underlying chunk reader allocations.
/// 3. Token Extraction: Parses unstructured terminal fragments using defensive string slicing and regular expressions into strongly-typed domain primitives.
abstract final class AdbProtocol {
  static const statusOkay = 'OKAY';
  static const statusFail = 'FAIL';

  /// Encodes a service request with its 4-digit hex length prefix.
  static Uint8List encodeRequest(String service) {
    final payload = ascii.encode(service);
    if (payload.length > 0xFFFF) {
      throw ArgumentError('adb service request too long: ${payload.length}');
    }
    final prefix = payload.length.toRadixString(16).padLeft(4, '0');
    return Uint8List.fromList([...ascii.encode(prefix), ...payload]);
  }

  /// Parses a 4-digit hex length prefix (e.g. `001d` -> 29).
  static int parseHexLength(List<int> fourBytes) {
    if (fourBytes.length != 4) {
      throw const AdbProtocolException('length prefix must be 4 bytes');
    }
    final text = ascii.decode(fourBytes, allowInvalid: false);
    final value = int.tryParse(text, radix: 16);
    if (value == null) {
      throw AdbProtocolException('invalid hex length prefix "$text"');
    }
    return value;
  }

  /// Parses the output of `host:devices` / `host:track-devices`.
  ///
  /// Each line is `<serial>\t<state>`. Track-devices snapshots use the same
  /// short format. An empty payload means no devices.
  static List<AdbDevice> parseDeviceList(String payload) {
    final devices = <AdbDevice>[];
    for (final line in const LineSplitter().convert(payload)) {
      if (line.trim().isEmpty) continue;
      final tab = line.indexOf('\t');
      final String serial;
      final String state;
      if (tab != -1) {
        serial = line.substring(0, tab).trim();
        state = line.substring(tab + 1).trim();
      } else {
        // Defensive: some adb builds separate with spaces.
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        serial = parts.first;
        state = parts[1];
      }
      if (serial.isEmpty) continue;
      devices.add(AdbDevice(serial: serial, state: AdbDeviceState.parse(state)));
    }
    return devices;
  }

  /// Extracts the phone's own WiFi IP from `adb shell ip route` output.
  ///
  /// Typical line:
  ///   `192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42`
  /// Returns null when the phone has no wlan address (e.g. WiFi off, or the
  /// phone is in hotspot mode, in which case the PC-side gateway IP should be
  /// used instead).
  static String? parseWlanIp(String ipRouteOutput) {
    final pattern = RegExp(
      r'dev\s+wlan\d+.*?\bsrc\s+(\d{1,3}(?:\.\d{1,3}){3})',
    );
    for (final line in const LineSplitter().convert(ipRouteOutput)) {
      final match = pattern.firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }
}

/// What `host:pair` answered, in terms a user can act on.
enum PairOutcome {
  /// The phone accepted the code; it is now paired with this PC.
  paired,

  /// The phone answered but rejected the code (wrong, or the pairing dialog
  /// on the phone was closed or timed out).
  wrongCode,

  /// Nothing answered at the pairing address.
  unreachable,

  /// Any other refusal; [PairResult.message] carries adb's own text.
  failed,
}

class PairResult {
  const PairResult(this.outcome, this.message, {this.guid});

  final PairOutcome outcome;

  /// adb's reply, never containing the pairing code.
  final String message;

  /// The `adb-<serial>-<suffix>` name of the paired phone, when adb says it.
  final String? guid;
}

/// Parsing and validation for `adb pair` (`host:pair:<code>:<host:port>`).
abstract final class AdbPairing {
  static final _address = RegExp(r'^(\d{1,3})(\.\d{1,3}){3}:(\d{1,5})$');
  static final _code = RegExp(r'^\d{6}$');

  /// True for an IPv4 `ip:port` with each octet 0-255 and a port 1-65535: the
  /// pairing address the phone shows. Anything else is refused before a
  /// request is built, so text cannot be injected into the service string.
  static bool isValidAddress(String value) {
    if (!_address.hasMatch(value)) return false;
    final colon = value.lastIndexOf(':');
    final port = int.parse(value.substring(colon + 1));
    if (port < 1 || port > 65535) return false;
    return value
        .substring(0, colon)
        .split('.')
        .every((octet) => int.parse(octet) <= 255);
  }

  /// True for the 6-digit pairing code.
  static bool isValidCode(String value) => _code.hasMatch(value);

  /// Classifies the text adb replies to `host:pair`, e.g.
  /// `Successfully paired to 192.168.1.8:37123 [guid=adb-XXXX-YYYY]` or
  /// `Failed: Wrong password or connection was dropped.`
  static PairResult parseResponse(String reply) {
    final text = reply.trim();
    final lower = text.toLowerCase();
    final guid = RegExp(r'guid=([^\]\s]+)').firstMatch(text)?.group(1);
    if (lower.startsWith('successfully paired')) {
      return PairResult(PairOutcome.paired, text, guid: guid);
    }
    if (lower.contains('password') || lower.contains('wrong code')) {
      return PairResult(PairOutcome.wrongCode, text);
    }
    if (lower.contains('unable to start') ||
        lower.contains('unable to connect') ||
        lower.contains('connection refused') ||
        lower.contains('timed out')) {
      return PairResult(PairOutcome.unreachable, text);
    }
    return PairResult(PairOutcome.failed, text.isEmpty ? 'no reply' : text);
  }
}

class AdbProtocolException implements Exception {
  const AdbProtocolException(this.message);
  final String message;

  @override
  String toString() => 'AdbProtocolException: $message';
}

/// Raised when the adb server answers `FAIL`.
class AdbServerException implements Exception {
  const AdbServerException(this.message);
  final String message;

  @override
  String toString() => 'AdbServerException: $message';
}
