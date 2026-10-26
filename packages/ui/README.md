# Voyager UI

Flutter Windows tray app for the Voyager daemon. It holds no device logic of its
own: it connects to the daemon's IPC port, shows the device list the daemon
pushes, and sends the same commands the daemon's stdin keys do (play, stop, go
wireless, handoff, retry a remembered phone).

## Run

The daemon must be running for the UI to show anything (start order does not
matter; the UI retries the connection every 2 seconds). From the repository
root:

```powershell
cd packages\daemon
dart pub get
dart run bin\daemon.dart
```

Then, in a second terminal:

```powershell
cd packages\ui
flutter pub get
flutter run -d windows
```

You need Flutter with Windows desktop support (Visual Studio with the C++
desktop workload); `flutter doctor` shows whether it is set up. CI uses Flutter
3.32.2.

The window starts hidden with a tray icon. It shows when a device becomes
ready, or when you click the tray icon; the close button hides it, and **Quit**
in the tray menu exits the UI only.

## Test

```powershell
cd packages\ui
flutter pub get
flutter analyze
flutter test
```

These need no daemon, phone or adb: the cubit tests use a fake repository.

## Structure

Feature-first Clean Architecture with Cubit for state:

- `lib/core/ipc/` keeps the connection to the daemon alive (`IpcConnection`).
- `lib/core/tray/` is the tray icon and menu.
- `lib/features/devices/` has `data/` (IPC-backed repository and JSON models),
  `domain/` (entities and the repository interface) and `presentation/` (the
  cubit and widgets).

The protocol lives in `packages/ipc`, shared with the daemon.

## Limits

- The port is fixed at 38765 (`kDefaultIpcPort`). The UI does not read the
  daemon's `config.json`, so a changed `ipcPort` there is not picked up.
- There is no settings screen yet.
