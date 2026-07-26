import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/config.dart';
import 'package:scrcpy_daemon/src/handoff.dart';
import 'package:scrcpy_daemon/src/known_devices.dart';
import 'package:scrcpy_daemon/src/scrcpy_launcher.dart';
import 'package:scrcpy_daemon/src/wireless.dart';
import 'package:scrcpy_daemon/src/wireless_reconnector.dart';
import 'package:scrcpy_ipc/scrcpy_ipc.dart';

/// Main execution engine and event coordinator for the scrcpy background daemon.
///
/// This application bootstraps local resource configurations, mounts low-level
/// hardware monitoring streams via an active `AdbClient`, and registers unified
/// terminal feedback loops to handle explicit runtime operations.
///
/// Concurrent Lifecycle Pipelines:
/// 1. Hardware State Tracking: Observes hardware topology shifts via infinite ADB socket subscriptions, executing state diffing and auto-launch policies.
/// 2. Interactive Terminal I/O: Exposes localized shell evaluation protocols to command manual network routing topology changes.
/// 3. IPC: Exposes the same operations to any connected UI over a loopback socket (packages/ipc). Both stdin and IPC drive the same functions.
/// 4. Resource Destruction: Binds platform signal listeners to ensure complete sub-process evacuation during abrupt termination.
Future<void> main(List<String> args) async {
  var config = await DaemonConfig.load();
  final adbPath = args.isNotEmpty ? args.first : config.adbPath;

  final client = AdbClient(adbPath: adbPath);
  late final IpcServer ipc;
  late final Timer reconnectTimer;
  final launcher = ScrcpyLauncher(
    scrcpyPath: config.scrcpyPath,
    baseArgs: config.scrcpyArgs,
    onExit: (serial, code) => ipc.broadcast(IpcEvent.scrcpyExited(serial, code)),
  );
  final wireless = WirelessManager(client);
  var knownWireless = await KnownDevicesStore.load();
  final reconnector = WirelessReconnector(client: client);

  stdout.writeln('config: ${DaemonConfig.configFile().path}');
  stdout.writeln('adb: $adbPath | scrcpy: ${config.scrcpyPath} | '
      'autoLaunch: ${config.autoLaunch}');

  var known = <String, AdbDevice>{};
  final modelNames = <String, String>{};
  // Serials with a handoff currently in flight, so the ambient auto-launch
  // below doesn't race it: `adb tcpip` restarts adbd, which briefly drops
  // and then reconnects the USB transport on its own (cable's still in),
  // and without this guard that reconnect looks like a fresh plug-in.
  final handoffInFlight = <String>{};
  // Debounces auto-launch: adb's own track-devices stream can keep flapping
  // (device -> offline -> unknown -> ... -> device) for a brief moment right
  // after a plug/replug as the connection actually settles. Launching the
  // instant the first `device` report arrives lands scrcpy's connection
  // attempt mid-flap and it fails, even though nothing is actually wrong.
  // Each becameReady re-triggers this and resets the timer, so a launch only
  // fires once the state has genuinely held steady.
  const autoLaunchDebounce = Duration(milliseconds: 500);
  final pendingLaunchTimers = <String, Timer>{};

  // Assigned before ipc.start() below, so a `quit` command can never arrive
  // while this is still unassigned.
  reconnectTimer = reconnector.startPeriodic(
    const Duration(seconds: 6),
    () => ReconnectSnapshot(
      cached: knownWireless,
      live: known,
      handoffInFlight: handoffInFlight,
    ),
    onTick: (reconnected) {
      for (final serial in reconnected) {
        stdout.writeln('[r] reconnect probe succeeded for $serial; '
            'waiting for track-devices to confirm');
      }
    },
  );

  Map<String, dynamic> deviceJson(AdbDevice d) => {
        'serial': d.serial,
        'state': d.state.name,
        if (modelNames[d.serial] != null) 'model': modelNames[d.serial],
        'mirroring': launcher.isRunning(d.serial),
      };

  List<Map<String, dynamic>> knownDevicesJson() =>
      knownWireless.values.map((d) => d.toJson()).toList();

  Future<void> rememberWireless(String usbSerial, String networkSerial) async {
    final parts = networkSerial.split(':');
    final model = modelNames[usbSerial] ?? await client.model(usbSerial);
    knownWireless = {
      ...knownWireless,
      usbSerial: KnownWirelessDevice(
        usbSerial: usbSerial,
        model: model,
        lastIp: parts[0],
        lastPort: int.parse(parts[1]),
      ),
    };
    await KnownDevicesStore.save(knownWireless);
    ipc.broadcast(IpcEvent.knownDevices(knownDevicesJson()));
  }

  Future<void> runGoWireless(String serial) async {
    final networkSerial = await wireless.goWireless(
      serial,
      onStatus: (stage, [detail]) =>
          ipc.broadcast(IpcEvent.wirelessStatus(serial, stage, detail)),
    );
    // On success the network device appears in track-devices and
    // autoLaunch opens the mirror by itself.
    if (networkSerial == null) {
      stdout.writeln('[w] gave up trying to reach $serial wirelessly');
    } else {
      await rememberWireless(serial, networkSerial);
    }
  }

  Future<void> runHandoff(String serial) async {
    if (!launcher.isRunning(serial)) {
      stdout.writeln('[h] no running USB mirror to hand off for $serial');
      return;
    }
    final name = modelNames[serial] ?? await client.model(serial);
    handoffInFlight.add(serial);
    try {
      final wirelessSerial = await handoff(
        client: client,
        launcher: launcher,
        usbSerial: serial,
        deviceName: name,
        onStatus: (stage, [detail]) =>
            ipc.broadcast(IpcEvent.handoffStatus(serial, stage, detail)),
      );
      if (wirelessSerial != null) {
        await rememberWireless(serial, wirelessSerial);
      }
    } finally {
      handoffInFlight.remove(serial);
    }
  }

  Future<void> runUsbMode(String serial) async {
    final device = known[serial];
    if (device == null || !device.isReady) return;
    if (device.isNetwork) {
      final parts = serial.split(':');
      await client.disconnectDevice(parts[0], int.parse(parts[1]));
      stdout.writeln('[u] disconnected $serial');
    } else {
      await client.usbMode(serial);
      stdout.writeln('[u] $serial back to USB-only (port closed)');
    }
  }

  void scheduleAutoLaunch(String serial, String name) {
    pendingLaunchTimers.remove(serial)?.cancel();
    pendingLaunchTimers[serial] = Timer(autoLaunchDebounce, () async {
      pendingLaunchTimers.remove(serial);
      final current = known[serial];
      if (current == null || !current.isReady) {
        // Flapped away again before settling; the next becameReady (if any)
        // will schedule a fresh attempt.
        return;
      }
      if (!config.autoLaunch) return;
      if (handoffInFlight.contains(serial)) {
        stdout.writeln('[=] skipping auto-launch for $serial; handoff in progress');
        return;
      }
      final launched = await launcher.launch(serial, windowTitle: name);
      stdout.writeln(launched
          ? '[>] scrcpy launched for $name'
          : '[=] scrcpy already running for $name');
    });
  }

  Future<void> onReady(AdbDevice device) async {
    final name = await client.model(device.serial);
    modelNames[device.serial] = name;
    final kind = device.isNetwork ? 'wireless' : 'USB';
    stdout.writeln('[+] $name (${device.serial}) connected via $kind');
    ipc.broadcast(IpcEvent.deviceReady(device.serial, model: name));

    scheduleAutoLaunch(device.serial, name);
  }

  ipc = IpcServer(
    onLog: (message) => stdout.writeln('[ipc] $message'),
    snapshot: () => [
      IpcEvent.devices(known.values.map(deviceJson).toList()),
      IpcEvent.knownDevices(knownDevicesJson()),
    ],
    onCommand: (request) async {
      String requireSerial() {
        final s = request.args['serial'];
        if (s is! String || s.isEmpty) throw 'missing "serial" argument';
        return s;
      }

      switch (request.cmd) {
        case IpcCommands.listDevices:
          return {'devices': known.values.map(deviceJson).toList()};
        case IpcCommands.launch:
          final serial = requireSerial();
          final launched = await launcher.launch(
            serial,
            windowTitle: modelNames[serial],
          );
          return {'launched': launched};
        case IpcCommands.stop:
          launcher.stop(requireSerial());
          return {};
        case IpcCommands.stopAll:
          launcher.stopAll();
          return {};
        case IpcCommands.goWireless:
          unawaited(runGoWireless(requireSerial()));
          return {'started': true};
        case IpcCommands.handoff:
          unawaited(runHandoff(requireSerial()));
          return {'started': true};
        case IpcCommands.usbMode:
          await runUsbMode(requireSerial());
          return {};
        case IpcCommands.retryReconnect:
          final serial = requireSerial();
          final entry = knownWireless[serial];
          if (entry == null) throw 'no cached wireless info for $serial';
          stdout.writeln('[r] manual retry requested for ${entry.networkSerial}');
          unawaited(reconnector.runOnce(ReconnectSnapshot(
            cached: {serial: entry},
            live: known,
            handoffInFlight: handoffInFlight,
          )).then((reconnected) {
            stdout.writeln(reconnected.isEmpty
                ? '[r] manual retry for ${entry.networkSerial} did not succeed'
                : '[r] manual retry succeeded for ${entry.networkSerial}; '
                    'waiting for track-devices to confirm');
          }));
          return {'started': true};
        case IpcCommands.getConfig:
          return config.toJson();
        case IpcCommands.setConfig:
          final incoming = request.args['config'];
          if (incoming is! Map<String, dynamic>) throw 'missing "config"';
          // adbPath/scrcpyPath/scrcpyArgs/ipcPort are baked into `client`,
          // `launcher`, and `ipc` at startup, so changes to those fields
          // only take effect after a daemon restart; autoLaunch is read
          // fresh on every device-ready event and applies immediately.
          config = DaemonConfig.fromJson(incoming, fallback: config);
          await config.save();
          return {};
        case IpcCommands.quit:
          // Delay past the reply write (which happens on the microtask
          // queue right after this returns) so the client sees the ack.
          unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () {
            reconnectTimer.cancel();
            launcher.stopAll();
            exit(0);
          }));
          return {};
        default:
          throw 'unknown command: ${request.cmd}';
      }
    },
  );

  try {
    await ipc.start(port: config.ipcPort);
    stdout.writeln('ipc: listening on 127.0.0.1:${config.ipcPort}');
  } on DaemonAlreadyRunning catch (e) {
    stdout.writeln('$e');
    exit(0);
  }

  stdout.writeln('starting adb server if needed...');
  await client.ensureServerRunning();
  stdout.writeln('adb server protocol version: ${await client.serverVersion()}');
  stdout.writeln('watching for devices | commands: '
      'w=wireless h=handoff u=usb l=list q=quit\n');

  ProcessSignal.sigint.watch().listen((_) {
    reconnectTimer.cancel();
    launcher.stopAll();
    exit(0);
  });

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) async {
    final command = line.trim().toLowerCase();
    switch (command) {
      case 'w':
        final usb =
            known.values.where((d) => d.isReady && !d.isNetwork).toList();
        if (usb.isEmpty) {
          stdout.writeln('[w] no USB device connected; plug in first');
          return;
        }
        unawaited(runGoWireless(usb.first.serial));
        break;
      case 'h':
        final handoffUsb = known.values
            .where((d) =>
                d.isReady && !d.isNetwork && launcher.isRunning(d.serial))
            .toList();
        if (handoffUsb.isEmpty) {
          stdout.writeln('[h] no running USB mirror to hand off; press '
              'l=list or launch one first');
          return;
        }
        unawaited(runHandoff(handoffUsb.first.serial));
        break;
      case 'u':
        for (final d in known.values.where((d) => d.isReady)) {
          await runUsbMode(d.serial);
        }
        break;
      case 'l':
        if (known.isEmpty) stdout.writeln('(no devices)');
        for (final d in known.values) {
          stdout.writeln('  ${d.serial}  ${d.state.name}'
              '${d.isNetwork ? "  (wireless)" : ""}'
              '${launcher.isRunning(d.serial) ? "  (mirroring)" : ""}');
        }
        break;
      case 'q':
        reconnectTimer.cancel();
        launcher.stopAll();
        exit(0);
      default:
        if (command.isNotEmpty) {
          stdout.writeln('commands: w=wireless h=handoff u=usb l=list q=quit');
        }
    }
  });

  while (true) {
    try {
      await for (final snapshot in client.trackDevices()) {
        final current = {for (final d in snapshot) d.serial: d};

        for (final device in current.values) {
          final previous = known[device.serial];
          final becameReady =
              device.isReady && (previous == null || !previous.isReady);
          if (previous == null) {
            _logAttached(device);
          } else if (previous.state != device.state) {
            stdout.writeln('[~] ${device.serial}: '
                '${previous.state.name} -> ${device.state.name}');
          }
          if (becameReady) {
            known = {...known, device.serial: device};
            await onReady(device);
          }
        }
        for (final serial in known.keys) {
          if (!current.containsKey(serial)) {
            stdout.writeln('[-] $serial disconnected');
            ipc.broadcast(IpcEvent.deviceGone(serial));
            pendingLaunchTimers.remove(serial)?.cancel();
          }
        }
        known = current;
        ipc.broadcast(IpcEvent.devices(known.values.map(deviceJson).toList()));
      }
      stdout.writeln('track-devices stream closed, reconnecting...');
    } catch (e) {
      stdout.writeln('adb server unreachable ($e), retrying in 2s...');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await client.ensureServerRunning();
  }
}

void _logAttached(AdbDevice device) {
  if (device.state == AdbDeviceState.unauthorized) {
    stdout.writeln('[!] ${device.serial} connected but unauthorized: '
        'accept the prompt on the phone');
  } else if (!device.isReady) {
    stdout.writeln(
        '[?] ${device.serial} attached in state ${device.state.name}');
  }
}
