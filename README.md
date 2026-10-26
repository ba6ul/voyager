# Voyager

Android screen mirroring on Windows, without the setup ritual. Plug your phone
in and the mirror opens. Go wireless over the phone's own hotspot, no wireless
debugging toggle, no shared WiFi required — and once a phone has gone wireless
once, the daemon remembers it and reconnects on its own next time.

Built on [scrcpy](https://github.com/Genymobile/scrcpy) and a pure Dart adb
client. For Flutter and Android developers who test on real hardware all day.

**Windows only for now.**

## The problem this solves

scrcpy's wireless path expects two things: Android's wireless debugging enabled,
and your PC and phone on the same WiFi network.

That breaks the moment you are on the phone's hotspot, which is the common case
when you are testing away from a desk. A phone cannot be a hotspot and a client
on some other WiFi at the same time. So you are back to a cable, or to typing
`adb tcpip 5555` and hunting for an IP by hand every session.

Voyager automates the legacy `tcpip` path instead. On a hotspot the phone *is*
the default gateway, so the daemon reads the gateway from the routing table and
connects to it. No toggle, no IP hunting, and the same code path also handles
the plain same-WiFi case.

## What works today

Verified against a real Pixel 10a.

| | Status |
|---|---|
| USB plug-and-play: plug in, mirror opens on its own | Working |
| Auto-launch on device ready, no clicks | Working |
| Go Wireless over the phone's hotspot, survives unplugging USB | Working |
| Handoff: one command swaps an active USB mirror to wireless in place | Working |
| Automatic reconnect: a phone that's gone wireless before reconnects on its own | Working |
| Flutter tray UI: device list, Play/Stop, Go Wireless, Handoff, retry of remembered phones | Early: builds and connects to the daemon; no settings screen yet |
| Installer with bundled adb/scrcpy binaries | Not started |

## Requirements

- Windows 10 or 11
- Dart SDK on PATH. Check with `dart --version`.
- `adb` and `scrcpy` on PATH, or their paths set in `config.json`. Bundled
  binaries are planned but not built yet — see the issue tracker.
- USB debugging enabled on the phone
- Only to run the tray UI: Flutter with Windows desktop support (Visual Studio
  with the C++ desktop workload). CI uses Flutter 3.32.2. Check with
  `flutter doctor`.

## Run it

There is no installer yet. Clone and run the daemon.

```powershell
git clone https://github.com/ba6ul/voyager.git
cd voyager

cd packages\core
dart pub get
cd ..\ipc
dart pub get
cd ..\daemon
dart pub get
dart run bin\daemon.dart
```

Plug your phone in. You should see the device name and serial appear, and a
scrcpy window open on its own.

If adb is not on PATH, pass it directly:

```powershell
dart run bin\daemon.dart "C:\platform-tools\adb.exe"
```

The daemon reads stdin while it runs:

| Key | Does |
|---|---|
| `w` | go wireless |
| `h` | handoff — swap an active USB mirror to wireless in place |
| `u` | back to USB only, closes port 5555 / disconnects a wireless address |
| `l` | list devices, with connection state and whether each is mirroring |
| `q` | quit — closes every mirror window and shuts the daemon down |

Config lives at `%APPDATA%\scrcpy_gui\config.json` and is created on first run.
It holds the adb path, the scrcpy path, `autoLaunch`, and the IPC port. A
second file, `known_wireless_devices.json` in the same folder, remembers which
devices have gone wireless before, for automatic reconnect.

## Run the tray UI (optional)

The UI is a separate process that talks to the running daemon. Start the daemon
as above, then in a second terminal:

```powershell
cd packages\ui
flutter pub get
flutter run -d windows
```

The window starts hidden and only a tray icon appears. It pops up when a
device becomes ready; click the tray icon to show it at any time. The close
button hides the window, and **Quit** in the tray menu exits the UI (the daemon
keeps running). The UI connects to `127.0.0.1:38765` and retries every 2
seconds, so it does not matter which one you start first. It does not read
`config.json`, so if you change `ipcPort` there the UI will not find the daemon.

## Going wireless

Two ways to do it, depending on whether a mirror is already open:

- **`w` (Go Wireless)** — switches the phone to TCP mode, walks you through
  hotspot/same-WiFi setup, then connects automatically. Doesn't manage windows
  for you; if a USB mirror is already open, you'll end up with two windows
  until you close one yourself or unplug.
- **`h` (Handoff)** — same underlying connection, but requires a mirror to
  already be running over USB, and closes that window automatically once the
  wireless one opens — feels like the window simply persisted.

Either way, once connected the phone is remembered: if it drops off later
(hotspot toggled, phone moved out of range) and comes back reachable, the
daemon reconnects it on its own within a few seconds — no `w`/`h` needed again.

> **Security:** an open port 5555 means anyone on that network can adb into
> your phone. On a phone hotspot that's a network of two, so the exposure is
> small, but it's real on a shared WiFi. Press `u` when you're done to close it.

## How it is put together

```
UI (Flutter Windows)      tray, device list popup       early; settings not built
        |  NDJSON over loopback TCP
Daemon (Dart CLI)         device tracking, launching,   working
        |                 wireless orchestration, reconnect cache
Core (pure Dart)          adb client, wire protocol     working
        |  TCP 5037
adb server
```

- **`packages/core`** speaks the adb server's binary protocol directly over TCP
  5037. No parsing `adb.exe` stdout, no subprocess per query. `AdbClient` exposes
  a `trackDevices()` stream for instant device events plus `tcpip()`,
  `connectDevice()`, and `shell()`. `FakeAdbServer` lets the whole thing be
  tested without a phone or a real adb server. Pure Dart, no platform deps, so
  it's usable as a standalone library.
- **`packages/daemon`** watches the device stream, spawns and kills scrcpy per
  device, runs the wireless/handoff flows, and keeps a small cache of devices
  that have gone wireless before so it can reconnect them automatically.
  Headless, so it's easy to debug and will later sit behind a tray icon.
- **`packages/ipc`** is the NDJSON message contract between daemon and UI, plus
  a loopback socket server and client — wired into the daemon, driving the same
  commands as the stdin interface.
- **`packages/ui`** is the Flutter Windows tray app. It is a thin client of the
  daemon: it connects to the IPC port, shows the device list the daemon pushes,
  and sends the same commands the stdin keys do. See
  [packages/ui/README.md](packages/ui/README.md).
- **`vendor/`** is where bundled adb and scrcpy builds will go for packaging.
  Not committed yet.

## Tests

Each package is tested on its own. None of the tests need a phone, adb, or
scrcpy: they use an in-process fake adb server, fake repositories, and
OS-assigned loopback ports.

```powershell
cd packages\core
dart pub get
dart test   # protocol units + fake-server integration

cd ..\ipc
dart pub get
dart test   # message parsing, command round trip, malformed input, shutdown

cd ..\daemon
dart pub get
dart test   # handoff, goWireless, gateway parsing, reconnect cache, error guards

cd ..\ui
flutter pub get
flutter test   # device list cubit
```

`dart analyze` (and `flutter analyze` in `packages\ui`) should report no
issues. CI runs analyze and test for `core`, `ipc` and `daemon` on Ubuntu and
Windows, and for `ui` when `packages/ui` or `packages/ipc` change.

## Known limitations

- The UI is early: a tray icon and device list, no settings screen. Anything
  else is done through `config.json` or the daemon's stdin keys.
- No installer — clone and run, adb/scrcpy must already be installed separately.
- The same physical phone can appear as more than one device entry (its USB
  serial and its wireless address aren't yet recognized as the same phone) —
  actively being worked on, see the issue tracker.
- Windows only. `packages/core` is portable, but the launcher and wireless
  gateway detection are not.

See the [issue tracker](https://github.com/ba6ul/voyager/issues) for the full,
current list of known bugs and planned work.

## License

TBD.

## Credits

All the actual mirroring is [scrcpy](https://github.com/Genymobile/scrcpy) by
Genymobile. This project is a Windows front end and an adb automation layer
around it.

Built by Babul Raj Singh.
