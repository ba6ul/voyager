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
| Flutter UI and tray icon | In progress, not published yet |
| Installer with bundled adb/scrcpy binaries | Not started |

## Requirements

- Windows 10 or 11
- Dart SDK on PATH. Check with `dart --version`.
- `adb` and `scrcpy` on PATH, or their paths set in `config.json`. Bundled
  binaries are planned but not built yet — see the issue tracker.
- USB debugging enabled on the phone

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
UI (Flutter Windows)      tray, popups, settings        in progress, unpublished
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
- **`packages/ui`** (Flutter Windows tray app) is in progress on a separate
  branch, not yet part of this published repo.
- **`vendor/`** is where bundled adb and scrcpy builds will go for packaging.
  Not committed yet.

## Tests

```powershell
cd packages\core
dart test   # 21 tests: protocol units + fake-server integration

cd ..\daemon
dart test   # 16 tests: handoff, wireless reconnect cache, reconnector logic
```

## Known limitations

- No UI yet — terminal only, via the daemon's stdin commands.
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
