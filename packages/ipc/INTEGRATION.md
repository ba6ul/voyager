# Wiring the IPC package into the daemon

## 1. Add the dependency

`packages/daemon/pubspec.yaml`:

```yaml
dependencies:
  scrcpy_core:
    path: ../core
  scrcpy_ipc:
    path: ../ipc
```

Then `dart pub get` in `packages/daemon`.

## 2. Add the port to config

In `config.dart`, add a field to `DaemonConfig`:

```dart
final int ipcPort; // default kDefaultIpcPort (38765)
```

Read and write it in `load()` / `save()` like the other fields.

## 3. Wire it into `bin/daemon.dart`

Keep a `List<AdbDevice> lastSnapshot = []` updated by the track loop, then:

```dart
import 'package:scrcpy_ipc/scrcpy_ipc.dart';

Map<String, dynamic> deviceJson(AdbDevice d) => {
      'serial': d.serial,
      'state': d.state.name,
      // add 'model' if you cache it when the device becomes ready
    };

final ipc = IpcServer(
  onLog: print,
  // New clients immediately get the current state:
  snapshot: () => [
    IpcEvent.devices(lastSnapshot.map(deviceJson).toList()),
  ],
  onCommand: (req) async {
    String requireSerial() {
      final s = req.args['serial'];
      if (s is! String || s.isEmpty) throw 'missing "serial" argument';
      return s;
    }

    switch (req.cmd) {
      case IpcCommands.listDevices:
        return {'devices': lastSnapshot.map(deviceJson).toList()};
      case IpcCommands.launch:
        final ok = launcher.launch(requireSerial());
        return {'launched': ok}; // false = already running for that serial
      case IpcCommands.stop:
        launcher.stop(requireSerial());
        return {};
      case IpcCommands.stopAll:
        launcher.stopAll();
        return {};
      case IpcCommands.goWireless:
        // Long-running with user steps: return immediately, then report
        // progress via wirelessStatus events (see section 4).
        unawaited(runWirelessWithEvents(requireSerial(), ipc));
        return {'started': true};
      case IpcCommands.usbMode:
        await client.usbMode(requireSerial());
        return {};
      case IpcCommands.getConfig:
        return config.toJson();
      case IpcCommands.setConfig:
        final incoming = req.args['config'];
        if (incoming is! Map<String, dynamic>) throw 'missing "config"';
        config = DaemonConfig.fromJson(incoming);
        await config.save();
        return {};
      case IpcCommands.quit:
        scheduleMicrotask(shutdown); // reply first, then exit
        return {};
      default:
        throw 'unknown command: ${req.cmd}';
    }
  },
);

try {
  await ipc.start(port: config.ipcPort);
} on DaemonAlreadyRunning catch (e) {
  print(e); // second instance: exit instead of double-tracking devices
  exit(0);
}
```

In the track-devices loop, alongside the existing logging:

```dart
lastSnapshot = snapshot;
ipc.broadcast(IpcEvent.devices(snapshot.map(deviceJson).toList()));
// where you already detect ready/gone transitions:
ipc.broadcast(IpcEvent.deviceReady(serial, model: model));
ipc.broadcast(IpcEvent.deviceGone(serial));
```

And where `ScrcpyLauncher` observes a process exit:

```dart
ipc.broadcast(IpcEvent.scrcpyExited(serial, exitCode));
```

## 4. Wireless progress events

Give `WirelessManager.goWireless` an optional callback:

```dart
Future<String?> goWireless(
  String serial, {
  void Function(String stage, [String? detail])? onStatus,
}) async { ... }
```

Call it at each step with the stage names from `IpcEvents.wirelessStatus`
(readingWifiIp, tcpipEnabled, waitingForHotspot, connecting, connected,
failed). Then:

```dart
Future<void> runWirelessWithEvents(String serial, IpcServer ipc) async {
  try {
    final net = await wireless.goWireless(serial, onStatus: (stage, [d]) {
      ipc.broadcast(IpcEvent.wirelessStatus(serial, stage, d));
    });
    if (net == null) {
      ipc.broadcast(IpcEvent.wirelessStatus(serial, 'failed', 'no route'));
    }
  } catch (e) {
    ipc.broadcast(IpcEvent.wirelessStatus(serial, 'failed', e.toString()));
  }
}
```

The existing stdin `w`/`u`/`l`/`q` commands can stay; both paths now call the
same functions, so behavior is identical whether input comes from the
console or a socket.

## 5. Test the loop

Terminal 1: `dart run bin/daemon.dart`
Terminal 2: `dart run tool/ipc_probe.dart`

Then: type `l`, plug/unplug the phone and watch `devices` events, `p <serial>`
to launch, `w <serial>` and follow the wirelessStatus stages through a real
hotspot run. Once all of that behaves, the Flutter UI is just this probe with
widgets instead of print statements.
