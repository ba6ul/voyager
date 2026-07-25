# scrcpy GUI

Frictionless Windows <-> Android mirroring on top of scrcpy.
Two core features: USB plug-and-play popup, and wireless that works over
the phone's own hotspot (no wireless debugging, no shared WiFi needed).

## Architecture

- `packages/core` - pure Dart. Talks the adb server protocol directly over
  TCP port 5037 (no stdout scraping). Fully unit tested against a fake
  in-process adb server.
- `packages/daemon` - Dart CLI, will become the tray daemon. Milestone 1 is
  a console device watcher.
- `packages/ui` - Flutter Windows app (popup + settings). Created in a later
  step with `flutter create`.
- `vendor/` - drop bundled `adb` (platform-tools) and `scrcpy` builds here
  for packaging. Not committed.

## Setup (Windows)

Prerequisite: Flutter SDK installed and on PATH (it ships Dart too).
Verify with `flutter doctor`.

```powershell
# 1. Core package: fetch deps and run the test suite
cd packages\core
dart pub get
dart test

# 2. Daemon milestone 1: live device watcher
cd ..\daemon
dart pub get
dart run bin\daemon.dart
# now plug / unplug your phone and watch the events

# If adb is not on PATH, point the daemon at a binary:
dart run bin\daemon.dart "C:\platform-tools\adb.exe"

# 3. (later) Create the Flutter UI package
cd ..
flutter create --platforms=windows --org com.haripin --project-name scrcpy_ui ui
```

## Wireless flow (planned)

1. Phone on USB, user clicks "Go wireless".
2. Daemon: `tcpip 5555` via AdbClient, and caches the phone's WiFi IP
   (`AdbClient.wifiIp`) for the same-network case.
3. User enables hotspot, connects the PC to it, unplugs.
4. Daemon detects the new interface; on a hotspot the phone IS the default
   gateway, so it runs `connectDevice(gatewayIp)`. Falls back to the cached
   WiFi IP.
5. Same popup, Play button, done. `usbMode()` is the one-click security
   off-switch (port 5555 open means anyone on the network can adb in).
