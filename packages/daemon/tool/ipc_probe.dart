import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_ipc/scrcpy_ipc.dart';

/// Manual verification tool for the daemon's IPC server (packages/ipc).
///
/// Run the daemon first (`dart run bin/daemon.dart`), then this
/// (`dart run tool/ipc_probe.dart`) in a second terminal. Every event the
/// daemon broadcasts is printed as it arrives; typed commands are sent as
/// IPC requests instead of stdin, so this exercises the exact path the
/// Flutter UI will use.
///
/// Commands: l (listDevices), p <serial> (launch/play), s <serial> (stop),
/// w <serial> (goWireless), h <serial> (handoff), u <serial> (usbMode), q (quit).
Future<void> main() async {
  final client = IpcClient();
  try {
    await client.connect();
  } catch (e) {
    stderr.writeln('could not connect to daemon on 127.0.0.1:$kDefaultIpcPort: $e');
    stderr.writeln('is the daemon running? (dart run bin/daemon.dart)');
    exit(1);
  }
  print('connected to daemon on 127.0.0.1:$kDefaultIpcPort');

  client.events.listen((event) {
    print('<- ${event.event} ${jsonEncode(event.data)}');
  });
  unawaited(client.onDisconnected.then((_) {
    print('daemon disconnected');
    exit(0);
  }));

  print('commands: l=list p/s/w/h/u <serial> q=quit');
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final parts = line.trim().split(RegExp(r'\s+'));
    final command = parts.isEmpty ? '' : parts.first.toLowerCase();
    final serial = parts.length > 1 ? parts[1] : null;

    try {
      switch (command) {
        case 'l':
          final result = await client.send(IpcCommands.listDevices);
          print('-> ${jsonEncode(result.data)}');
          break;
        case 'p':
          _requireSerial(serial);
          final result =
              await client.send(IpcCommands.launch, {'serial': serial});
          print('-> ${jsonEncode(result.data)}');
          break;
        case 's':
          _requireSerial(serial);
          await client.send(IpcCommands.stop, {'serial': serial});
          break;
        case 'w':
          _requireSerial(serial);
          await client.send(IpcCommands.goWireless, {'serial': serial});
          break;
        case 'h':
          _requireSerial(serial);
          await client.send(IpcCommands.handoff, {'serial': serial});
          break;
        case 'u':
          _requireSerial(serial);
          await client.send(IpcCommands.usbMode, {'serial': serial});
          break;
        case 'q':
          await client.send(IpcCommands.quit);
          await client.close();
          exit(0);
        case '':
          break;
        default:
          print('commands: l=list p/s/w/h/u <serial> q=quit');
      }
    } catch (e) {
      print('error: $e');
    }
  }
}

void _requireSerial(String? serial) {
  if (serial == null || serial.isEmpty) {
    throw ArgumentError('usage: <command> <serial>');
  }
}
