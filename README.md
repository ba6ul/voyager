# Voyager

Android screen mirroring on Windows, without the setup ritual. Plug your phone
in and the mirror opens. Go wireless over the phone's own hotspot, no wireless
debugging toggle, no shared WiFi.

Built on [scrcpy](https://github.com/Genymobile/scrcpy) and a pure Dart adb
client. For Flutter and Android developers who test on real hardware all day.

**Windows only for now.** Current version: v0.3.0.

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
the plain same WiFi case.

## What works today

All three verified on a Pixel 10a, 25 July 2026.

| | Status |
|---|---|
| USB plug-and-play: plug in, mirror opens in about 1 second | Working |
| Auto-launch on device ready, no clicks | Working |
| Wireless over the phone's hotspot, survives unplugging USB | Working |
| Flutter UI and tray icon | Not yet, see roadmap |
| Installer with bundled binaries | Not yet, see roadmap |

<!-- TODO: drop two GIFs here.
     1. plug in -> mirror window opens
     2. type w, enable hotspot, unplug, mirror keeps running -->

## Requirements

- Windows 10 or 11
- Flutter SDK on PATH (it ships Dart, which is what actually runs). Check with
  `flutter doctor`.
- `adb` and `scrcpy` on PATH, or their paths set in `config.json`. Bundled
  binaries come in a later milestone.
- USB debugging enabled on the phone

## Run it

There is no installer yet. Clone and run the daemon.

```powershell
# fetch deps and confirm the adb client works on your machine
cd packages\core
dart pub get
dart test

# start the daemon
cd ..\daemon
dart pub get
dart run bin\daemon.dart
```

Plug your phone in. You should see the device name and serial appear, and a
scrcpy window open.

If adb is not on PATH, pass it directly:

```powershell
dart run bin\daemon.dart "C:\platform-tools\adb.exe"
```

The daemon reads stdin while it runs:

| Key | Does |
|---|---|
| `w` | go wireless |
| `u` | back to USB only, closes port 5555 |
| `l` | list devices |
| `q` | quit |

Config lives at `%APPDATA%\scrcpy_gui\config.json` and is created on first run.
It holds the adb path, the scrcpy path, and an `autoLaunch` flag.

## Going wireless

1. Phone on USB. Type `w`.
2. The daemon runs `tcpip 5555` and caches the phone's WiFi IP.
3. Enable the phone's hotspot and connect your PC to it. Unplug USB.
4. The daemon reads default gateways from `route print` and tries `adb connect`
   on each, then falls back to the cached WiFi IP.
5. The mirror keeps running.

> **Security:** port 5555 open means anyone on that network can adb into your
> phone. On a phone hotspot that is a network of two, so the exposure is small,
> but it is real on a shared WiFi. Press `u` when you are done to close it.

## How it is put together

Three layers, each independently testable. The daemon does the work; the UI,
when it lands, is a thin dashboard on top of it.

```
UI (Flutter Windows)      tray, popups, settings        milestone 5
        |  NDJSON over loopback TCP
Daemon (Dart CLI)         device tracking, launching,   working
        |                 wireless orchestration
Core (pure Dart)          adb client, wire protocol     working
        |  TCP 5037
adb server
```

- **`packages/core`** speaks the adb server's binary protocol directly over TCP
  5037. No parsing `adb.exe` stdout, no subprocess per query. `AdbClient` exposes
  a `trackDevices()` stream for instant device events plus `tcpip()`,
  `connectDevice()`, and `shell()`. `FakeAdbServer` lets the whole thing be
  tested without a phone or a real adb server. Pure Dart, no platform deps, so
  it is usable as a standalone library.
- **`packages/daemon`** watches the device stream, spawns and kills scrcpy per
  device, and runs the wireless handoff. Headless, so it is easy to debug and
  will later sit behind the tray icon.
- **`packages/ipc`** is the NDJSON message contract between daemon and UI, plus
  a loopback socket server and client. Scaffolded and importable, not wired into
  the daemon yet. See `packages/ipc/INTEGRATION.md` for the schema.
- **`packages/ui`** is empty until milestone 5.
- **`vendor/`** is where bundled adb and scrcpy builds go for packaging. Not
  committed.

Longer writeups: [ARCHITECTURE.md](ARCHITECTURE.md) for layers, data flow, and
the reasoning behind each decision. [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
for a file by file guide.

## Tests

```powershell
cd packages\core
dart test
# 21 passing: 7 protocol unit tests, 8 fake-server integration tests, plus the rest
```

The daemon has a handoff test scaffold that is currently skipped, waiting on
milestone 4.

## Roadmap

- **Milestone 4:** one-step handoff command. Type `h` and an active USB mirror
  moves to wireless, new window up before the old one closes.
- **Milestone 5:** Flutter Windows UI. Tray icon, device popup, settings. IPC
  replaces the stdin commands.
- **Milestone 6:** bundled adb and scrcpy, Windows installer, startup
  integration, code signing.

## Known limitations

- No UI. Terminal only.
- No installer. Clone and run.
- adb and scrcpy are not bundled yet.
- Windows only. `packages/core` is portable, but the launcher and tray are not.

## License

TBD.

## Credits

All the actual mirroring is [scrcpy](https://github.com/Genymobile/scrcpy) by
Genymobile. This project is a Windows front end and an adb automation layer
around it.

Built by Babul Raj Singh.
