# UI workspaces: what exists and what each one needs from the backend

Refs #73. This describes the retro handheld UI in `packages/ui` as built: what is real, what is a mock-up, and what the backend has to provide to make each mock-up real. Use it as the checklist when working on a feature's backend.

Legend: **REAL** talks to the daemon today. **MOCK** is presentation only; nothing reaches the phone.

## How the UI is put together

```
packages/ui/lib/
  main.dart                 window setup, tray, creates the cubit and the app
  app/
    voyager_shell.dart      header, nav keys, LCD frame, status bar, F1-F4
    app_section.dart        the four workspaces (enum)
  core/
    theme/                  RetroPalette (3 palettes), buildRetroTheme, ThemeController
    widgets/                PixelBorder, PixelPanel, PixelIcon, SegmentBar, PixelKey, PixelChip...
    daemon/daemon_launcher.dart   starts the daemon (dev setup)
    ipc/ipc_connection.dart       existing: reconnecting IPC client
  features/
    devices/                existing feature: cubit, repository, device list and rows
    home/                   Home workspace: unit status, quick ops, console
    flutter_dev/            Flutter workspace
    file_share/             Files workspace
    recording/              Recording workspace
```

- Every workspace reads devices from `DeviceListCubit` (the daemon's live list). Mock panels are built from constants in their own file.
- Anything unwired either shows a "coming soon" notice (`showNotWired`) or runs a labelled simulation (`DEMO`, `SOON`, `SIM`, `SIMULATION` badges).
- Window: 980x640, minimum 760x520 (`minWindowSize` in `main.dart`). `voyager_shell_test.dart` lays out every workspace at both sizes.
- F1-F4 switch workspace. Esc hides the window. The header buttons cycle the palette and toggle scanlines (not persisted).
- Fonts: Press Start 2P (labels) and VT323 (body), SIL OFL, bundled in `assets/fonts` with licences.

## Daemon commands the UI already uses (IPC, `packages/ipc`)

`listDevices`, `launch`, `stop`, `stopAll`, `goWireless`, `handoff`, `usbMode`, `retryReconnect`, `getConfig`, `setConfig`, `quit`. Events: `devices`, `deviceReady`, `deviceGone`, `scrcpyExited`, `wirelessStatus`, `handoffStatus`, `log`, `knownDevices`.

Not yet used by the UI: `setConfig`, the `log` event, `listDevices` (the `devices` event is used instead).

## 1. Home / Device Control (F1)

| Part | State | Notes |
|---|---|---|
| UNITS panel (`devices/.../device_list.dart`, `device_row.dart`, `pending_reconnect_row.dart`) | REAL | Play, Stop, Go Wireless, Handoff, Disconnect, Try Now; connecting, unreachable, empty and not-ready states. Unchanged behaviour, restyled. |
| Start service button | REAL (dev only) | In the unreachable state. `LocalDaemonLauncher` finds `packages/daemon` above the exe and runs `dart run bin/daemon.dart` detached. Needs the Dart SDK on PATH and the repo layout; the installer must replace it with a bundled daemon. Daemon output is not captured. |
| UNIT STATUS (`unit_status_panel.dart`) | PARTLY | Model, link, state, mirroring are REAL. BATT and DISK are fixed placeholder values (marked `BATT/DISK DEMO`). |
| Quick ops (`home_workspace.dart`) | MOCK | SHOT, APK, PUSH, BOOT, WIFI, LOGS show a coming-soon notice. |
| CONSOLE (`console_commands.dart`, `adb_console_panel.dart`) | REAL for daemon commands | See below. |

Console commands (all go through existing IPC): `devices`, `play`, `stop`, `stopall`, `wireless`, `handoff`, `usb`, `config`, `restart`, `quit`, `clear`, `help`. A `[unit]` argument is part of a serial or model; default is the first ready unit. `restart` = `quit`, wait for the connection to drop, start the daemon with the launcher, wait for it to return. `adb`, `shell`, `logcat`, `install`, `push`, `pull` answer "coming soon".

Backend work to make the MOCK parts real:
- **Device telemetry** (battery, disk, Android version, resolution): a new IPC command or extra fields on each device in the `devices` event, filled from `adb shell dumpsys battery`, `df`, `getprop`. Core would need matching `AdbClient` helpers.
- **Raw adb / shell in the console**: a new IPC command (for example `adb` with `{serial, args}`) that runs a command through `AdbClient.shell` or the adb binary, streams output as events, and has a timeout and an allow/deny decision (see backlog item on restricting IPC).
- **Quick ops**: screenshot (`screencap` + pull), install APK (`adb install`), push file, reboot, Wi-Fi toggle, logcat stream. Each is one IPC command; logcat needs a streaming event.
- **Daemon log in the UI**: the `log` event exists in the protocol but the daemon does not broadcast daemon output through it yet; the console could show it.
- **Daemon restart from the daemon side** (optional): today restart is UI-driven.

## 2. Flutter / App Development (F2)

| Part | State |
|---|---|
| PROJECTS list (3 fake projects, select one) | MOCK |
| APPS ON UNIT (fake package list; tapping shows coming soon) | MOCK |
| RUN CONFIG: target is the first ready real unit (REAL read), project, entry and mode chips are local state | MOCK |
| RUN, RELOAD, RESTART, STOP | SIMULATION: a timer prints a scripted `flutter run` log, prefixed `[SIM]` |
| DEVTOOLS, + OPEN | coming-soon notice |

Backend work:
- **Project discovery**: scan configured folders for `pubspec.yaml` with a Flutter SDK dependency; return name, path, SDK version. New IPC command (`listProjects`) plus a config key for search roots (`setConfig`).
- **Installed apps**: `adb shell pm list packages -3` and labels; new command (`listPackages {serial}`), and `launchApp {serial, package}` via `monkey` or `am start`.
- **Run / hot reload**: spawn `flutter run -d <serial>` in the project, keep the process in the daemon, stream stdout as events, send `r` / `R` / `q` to its stdin for reload, restart, stop. Needs a Flutter SDK path in config. Reload and restart map directly to the three buttons.
- **DevTools**: read the VM service URL from `flutter run` output and open it.
- The UI side then replaces the timer in `flutter_workspace.dart` with cubit state fed by those events.

## 3. Files / Transfer (F3)

| Part | State |
|---|---|
| PC pane, PHONE pane (fixed fake listings; select files; folders show coming soon) | MOCK |
| SEND / PULL | SIMULATION: queues the selected files and animates progress |
| QUEUE, CLEAR DONE | SIMULATION |
| Drop zone | coming-soon notice |

Backend work:
- **Phone listing**: `adb shell ls -l` (or `adb sync`-style listing) as `listFiles {serial, path}`.
- **PC listing**: can be done in the UI with `dart:io`; no daemon needed. Drag and drop needs a desktop drop package on the UI side.
- **Transfer**: `adb push` and `adb pull` as `transfer {serial, direction, source, dest}`, with progress events (`transferProgress {id, bytes, total}`), cancel, and a queue that runs one at a time (the UI already behaves this way). Handle wireless devices the same way as USB.
- The queue state (ids, progress, done) should live in a cubit once real; today it is local widget state.

## 4. Recording / Monitor (F4)

| Part | State |
|---|---|
| Channel chips (CH1.. = real connected units) | REAL read |
| MONITOR tube (test pattern, source name, timecode) | MOCK: no video |
| REC, PAUSE, STOP | SIMULATION: counts a timecode, wobbles the L/R meters, adds a clip entry on stop |
| LEVELS | SIMULATION |
| SETUP chips (720P/1080P, 30/60, audio) | local state, not sent anywhere |
| CLIPS list | MOCK |
| SNAP | coming-soon notice |

Backend work:
- **Recording**: scrcpy supports `--record <file>` (and `--no-playback`); a `startRecording {serial, options}` command that launches scrcpy with those arguments, `stopRecording {serial}`, and events with elapsed time. Resolution (`--max-size`), fps (`--max-fps`) and audio flags map from the SETUP chips. Pause is not supported by scrcpy; either drop it or stop and start a new segment.
- **Clips**: a recordings folder in config, and `listClips` reading it (file name, duration via ffprobe or scrcpy metadata, size). Playing and deleting are UI or OS actions.
- **Live monitor**: scrcpy renders in its own window, so an in-app preview needs either embedding that window or a frame stream (for example `adb exec-out screenrecord --output-format=h264`) decoded in Flutter. This is the biggest open design question for this workspace.
- **Audio levels** need an audio source from scrcpy (Android 11+); decide whether the meters are worth it.
- **Screenshots (SNAP)**: same as the Home quick op.

## Cross-cutting backend items this UI will want

- **Settings screen** (`SETUP` key is a coming-soon notice): edit `config.json` through `getConfig` / `setConfig`; persist the palette and scanline choice (today session only).
- **Per-unit identity**: workspaces select units by serial; the known gap about one phone appearing under several serials (USB, wifi, hotspot) applies to Files, Recording and Flutter targets as well.
- **Streaming events** (log lines, transfer progress, run output) will want a simple per-operation id convention in the IPC protocol.
- **Security**: the open backlog item on restricting IPC (token, validating serials and paths) matters more once the daemon runs shell commands and moves files.

## Tests that guard this

- `test/app/voyager_shell_test.dart`: shell, F-keys, every workspace at minimum and default size, console, palette cycle, simulated run.
- `test/features/home/console_commands_test.dart`: every console command, unit matching, restart flow.
- `test/features/devices/start_daemon_test.dart`: the Start service button.
- `test/core/theme/retro_palette_test.dart`: 4.5:1 text contrast for every palette.
- Existing `test/features/devices/*`: the device list behaviour, unchanged in intent.
