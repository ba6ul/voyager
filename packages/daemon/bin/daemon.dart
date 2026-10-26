import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/config.dart';
import 'package:scrcpy_daemon/src/device_tracker.dart';
import 'package:scrcpy_daemon/src/guarded.dart';
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
void main(List<String> args) {
  // Last-resort net: log an error nothing else handled instead of letting it
  // end the process. Expected failures are handled where they happen (see
  // `guarded` and the flows below); this only keeps the daemon up when one
  // slips through.
  runZonedGuarded(
    () => _run(args),
    (error, stack) => stderr.writeln('[!] unhandled error: $error\n$stack'),
  );
}

Future<void> _run(List<String> args) async {
  var config = await DaemonConfig.load();
  final adbPath = args.isNotEmpty ? args.first : config.adbPath;

  final client = AdbClient(adbPath: adbPath);
  late final IpcServer ipc;
  late final Timer reconnectTimer;
  // Assigned once deviceJson/known exist below; closing a scrcpy window
  // (its own X button, a crash) doesn't change adb's connection state, so
  // the track-devices loop never re-broadcasts on its own. Without this,
  // the UI's cached `mirroring` flag goes stale: it keeps showing "Stop"
  // for a device that already stopped mirroring.
  late final void Function() broadcastDevices;
  final launcher = ScrcpyLauncher(
    scrcpyPath: config.scrcpyPath,
    baseArgs: config.scrcpyArgs,
    onExit: (serial, code) {
      ipc.broadcast(IpcEvent.scrcpyExited(serial, code));
      broadcastDevices();
    },
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

  broadcastDevices =
      () => ipc.broadcast(IpcEvent.devices(known.values.map(deviceJson).toList()));

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

  // The device is already wireless by the time this runs, so a failure to
  // cache it only costs the later auto-reconnect; it must not turn a
  // successful flow into a reported failure.
  Future<void> rememberWirelessSafely(
      String usbSerial, String networkSerial) async {
    try {
      await rememberWireless(usbSerial, networkSerial);
    } catch (e) {
      stdout.writeln('[=] $networkSerial connected, but $usbSerial could not '
          'be saved for auto-reconnect: $e');
    }
  }

  // Both flows run fire-and-forget (IPC command, stdin key), so an error that
  // escapes them would end the daemon. goWireless/handoff report the failures
  // they expect through onStatus; `guarded` catches anything else and sends
  // the same `failed` status so a UI is not left waiting.
  Future<void> runGoWireless(String serial) => guarded(
        'goWireless $serial',
        () async {
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
            await rememberWirelessSafely(serial, networkSerial);
          }
        },
        onError: (error, _) => ipc.broadcast(
            IpcEvent.wirelessStatus(serial, 'failed', error.toString())),
      );

  Future<void> runHandoff(String serial) => guarded(
        'handoff $serial',
        () async {
          if (!launcher.isRunning(serial)) {
            stdout.writeln('[h] no running USB mirror to hand off for $serial');
            return;
          }
          var name = modelNames[serial];
          if (name == null) {
            try {
              name = await client.model(serial);
            } catch (_) {
              name = serial; // the name only titles the new window
            }
          }
          // A Go Wireless that timed out may still complete; make sure the
          // phone is back and ready before sending it anything new.
          if (!await wireless.settle(serial)) {
            stdout.writeln('[h] $serial has not settled after a previous '
                'attempt; not starting a handoff');
            ipc.broadcast(IpcEvent.handoffStatus(
                serial,
                'failed',
                'the phone has not come back since the last attempt to switch '
                    'it to TCP mode; wait for it to reconnect and try again'));
            return;
          }
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
              await rememberWirelessSafely(serial, wirelessSerial);
            }
          } finally {
            handoffInFlight.remove(serial);
          }
        },
        onError: (error, _) => ipc.broadcast(
            IpcEvent.handoffStatus(serial, 'failed', error.toString())),
      );

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
    // Timer callbacks are not awaited by anyone, so launch errors (e.g. a
    // missing scrcpy.exe throws ProcessException) must be caught here.
    pendingLaunchTimers[serial] = Timer(autoLaunchDebounce, () => guarded(
      'auto-launch for $name',
      () async {
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
        final result = await launcher.launch(serial, windowTitle: name);
        stdout.writeln(result == LaunchResult.started
            ? '[>] scrcpy launched for $name'
            : '[=] scrcpy already running for $name');
      },
      onError: (error, _) => ipc.broadcast(
          IpcEvent.log('could not start scrcpy for $name: $error')),
    ));
  }

  // Owns the per-snapshot logic. A device becoming ready is handled off the
  // tracking loop (see DeviceTracker), so a slow model lookup cannot stall it.
  final tracker = DeviceTracker(
    client: client,
    modelNames: modelNames,
    onReady: (device, name) async {
      final kind = device.isNetwork ? 'wireless' : 'USB';
      stdout.writeln('[+] $name (${device.serial}) connected via $kind');
      ipc.broadcast(IpcEvent.deviceReady(device.serial, model: name));

      scheduleAutoLaunch(device.serial, name);
    },
    onGone: (serial) {
      ipc.broadcast(IpcEvent.deviceGone(serial));
      pendingLaunchTimers.remove(serial)?.cancel();
    },
    onChanged: (current) {
      known = current;
      broadcastDevices();
    },
  );

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
          final result = await launcher.launch(
            serial,
            windowTitle: modelNames[serial],
          );
          return {
            'launched': result == LaunchResult.started,
            'alreadyRunning': result == LaunchResult.alreadyRunning,
          };
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
          // Answer with the outcome (one bounded `adb connect`, at most its
          // 5 s timeout) so the UI can show it; it used to reply "started"
          // and leave the result in this log only.
          final outcome = await reconnector.retryNow(
            entry,
            ReconnectSnapshot(
              cached: {serial: entry},
              live: known,
              handoffInFlight: handoffInFlight,
            ),
          );
          stdout.writeln(switch (outcome) {
            ManualRetryOutcome.reconnected =>
              '[r] manual retry succeeded for ${entry.networkSerial}; '
                  'waiting for track-devices to confirm',
            ManualRetryOutcome.unreachable =>
              '[r] manual retry for ${entry.networkSerial} did not succeed',
            ManualRetryOutcome.skipped =>
              '[r] manual retry for ${entry.networkSerial} skipped: already '
                  'connected or a wireless flow is running',
          });
          return {'outcome': outcome.name, 'address': entry.networkSerial};
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
  try {
    await client.ensureServerRunning();
    stdout.writeln('adb server protocol version: ${await client.serverVersion()}');
  } catch (e) {
    // The device-tracking loop below retries every 2 s, so keep the daemon
    // (and its IPC server) up rather than ending the process.
    stdout.writeln('adb server not available yet ($e), will keep retrying');
  }
  stdout.writeln('watching for devices | commands: '
      'w=wireless h=handoff u=usb p=play l=list q=quit\n');

  ProcessSignal.sigint.watch().listen((_) {
    reconnectTimer.cancel();
    launcher.stopAll();
    exit(0);
  });

  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => guarded('command "${line.trim()}"', () async {
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
      case 'p':
        final toLaunch = known.values
            .where((d) => d.isReady && !launcher.isRunning(d.serial))
            .toList();
        if (toLaunch.isEmpty) {
          stdout.writeln('[p] nothing to launch; every ready device is '
              'already mirroring');
          break;
        }
        for (final d in toLaunch) {
          final name = modelNames[d.serial] ?? d.serial;
          final result = await launcher.launch(d.serial, windowTitle: name);
          stdout.writeln(result == LaunchResult.started
              ? '[>] scrcpy launched for $name'
              : '[=] scrcpy already running for $name');
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
          stdout.writeln('commands: w=wireless h=handoff u=usb p=play l=list q=quit');
        }
    }
  }));

  while (true) {
    try {
      await for (final snapshot in client.trackDevices()) {
        tracker.handleSnapshot(snapshot);
      }
      stdout.writeln('track-devices stream closed, reconnecting...');
    } catch (e) {
      stdout.writeln('adb server unreachable ($e), retrying in 2s...');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      await client.ensureServerRunning();
    } catch (e) {
      // adb missing or start-server failing must not end the daemon; the
      // next pass of this loop tries again.
      stdout.writeln('could not start the adb server ($e), retrying in 2s...');
    }
  }
}
