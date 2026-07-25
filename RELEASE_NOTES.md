# Release Notes: v0.3.0

**Date:** 25 July 2026  
**Status:** Three milestones complete and verified on real hardware  
**Breaking Changes:** None (first public release)

---

## What's New

This release introduces a **production-ready adb client library** and **fully-working wireless Android mirroring** with zero "wireless debugging" toggle nonsense. Two core features, both tested:

1. **USB Plug-and-Play**: Phone plugs in → mirror opens in ~1 second. No clicks.
2. **Wireless over Hotspot**: Phone's hotspot + PC joins it → mirror works. No special WiFi setup.

---

## The Big Jump: From Scaffolding to Working Code

Public repo structure went from "Flutter placeholder + empty folders" to **three working packages**:

### New: `scrcpy_core` Package (Pure Dart ADB Client)

**What it is:** A Dart library that speaks the adb server's binary protocol directly (no `adb.exe` stdout scraping, no subprocess overhead).

**Key classes:**
- `AdbClient`: main API—`trackDevices()` stream (instant device events), `tcpip()`, `connectDevice()`, `shell()`, model name fetching, WiFi IP reading.
- `AdbProtocol`: wire protocol encoding/decoding. Parses device lists, hex lengths, state transitions.
- `ByteReader`: buffered socket reader (adb protocol needs exact-byte boundaries; this handles the chunking).
- `AdbDevice`: model for connected device state (USB serial, IP:port, authorization status).
- `FakeAdbServer`: in-process test double (lets you test the client without a real adb server or phone).

**Testing:**
- `protocol_test.dart`: 7 unit tests (encoding, parsing, no I/O).
- `fake_server_test.dart`: 8 integration tests (real client vs fake server, all handshakes).
- **All 21 tests passing** on Windows (verified 25 July).

**Why it matters:** Reliable device detection (no polling, no text scraping). Fast (direct TCP, no process spawn). Portable (pure Dart).

### New: `scrcpy_daemon` Package (Headless Mirror Orchestrator)

**What it is:** A Dart CLI app that watches for device changes, launches/closes scrcpy windows, and orchestrates wireless connections. Runs in background, no UI yet (Flutter UI comes in milestone 5).

**Key modules:**
- `bin/daemon.dart`: entry point. Runs forever, listens to `trackDevices()` stream, responds to stdin commands (w=wireless, u=usb-only, l=list, q=quit).
- `config.dart`: loads/saves `%APPDATA%\scrcpy_gui\config.json` (adb path, scrcpy path, autoLaunch flag). Created on first run.
- `scrcpy_launcher.dart`: spawns `scrcpy.exe` per device, tracks instances, kills on demand, logs exit codes.
- `wireless.dart`: implements the hotspot/WiFi handoff:
  - `tcpip 5555` to put phone in TCP mode (no wireless debugging toggle needed).
  - Polls Windows `route print` to find default gateways (phone appears as one on hotspot mode).
  - Tries `adb connect` to each gateway, then cached WiFi IP.
  - Waits for device to appear in adb devices and be ready.
  - Returns success or timeout.

**Testing:**
- `handoff_test.dart`: skeleton for choreography tests (will verify USB→wireless transition order). Currently skipped, ready to be filled.

**Verified on:**
- Pixel 10a (USB): instant detection, auto-launch, model name fetched.
- Pixel 10a (wireless): hotspot mode, auto-connect, seamless.

### New: `scrcpy_ipc` Package (Daemon ↔ UI Communication)

**What it is:** Newline-JSON (NDJSON) protocol for daemon-to-UI and UI-to-daemon messages. Not yet integrated into daemon (still using stdin for testing), but ready for milestone 5 (Flutter UI).

**Key files:**
- `messages.dart`: message types (LaunchRequest, GoWirelessRequest, DeviceUpdate, etc.), JSON serializable.
- `ipc_server.dart`: daemon-side socket server (listens on loopback, handles incoming commands).
- `ipc_client.dart`: UI-side socket client (connects to daemon, sends commands, receives device updates).
- `INTEGRATION.md`: protocol specification (message schema, examples).

**Status:** Scaffolded, tested to import without errors. Integration into daemon + Flutter UI comes in milestone 5.

---

## Verified Workflows

### Milestone 1: USB Plug-and-Play ✅
**Test:** Plug Pixel 10a via USB.  
**Expected:** Daemon logs device name and serial, scrcpy window opens.  
**Result:** ✅ Works instantly (~1 second from plug to window).

**Code:** `AdbClient.trackDevices()` stream + `ScrcpyLauncher.launch()`.

### Milestone 2: Auto-Launch scrcpy ✅
**Test:** Edit config.json to set `autoLaunch: true`, plug phone.  
**Expected:** Mirror opens automatically on device ready.  
**Result:** ✅ Window pops up without user clicking anything.

**Code:** `DaemonConfig` + `ScrcpyLauncher` + ready-state detection.

### Milestone 3: Wireless over Hotspot ✅
**Test:** Type `w` in daemon, turn on phone hotspot, connect PC to it, unplug USB.  
**Expected:** Mirror transitions from USB to wireless, keeps working after unplug.  
**Result:** ✅ Seamless transition, wireless connection stable.

**Code:** `WirelessManager.goWireless()` + `route print` gateway detection + `adb connect`.

---

## What Changed from Scaffolding

**Before (public repo at start of development):**
- Root-level Flutter `pubspec.yaml` (placeholder for UI, no code).
- Empty `packages/ui/` folder.
- Empty `vendor/` placeholders.
- No working daemon, no adb client, no tests.

**After (this release):**
- `packages/core/`: 1000+ lines of production adb client code + 21 passing tests.
- `packages/daemon/`: 500+ lines of daemon + wireless + launcher code.
- `packages/ipc/`: 400+ lines of IPC protocol + client/server.
- `packages/daemon/test/`: handoff test scaffold ready for milestone 4.
- All dependencies resolve, all imports valid, no circular deps.
- Comprehensive documentation: ARCHITECTURE.md (495 lines), PROJECT_STRUCTURE.md (305 lines), README.md.

**Why the big jump:**
Development was incremental (21 commits on main private repo), but the public repo was kept clean—only synced when milestones were solid. This release packages three fully-working milestones at once.

---

## Architecture Overview

```
┌─────────────────────────────────────┐
│  UI Layer (Flutter Windows)         │  ← milestone 5
│  - Tray, popups, settings           │
└─────────────────┬───────────────────┘
                  │ IPC (NDJSON over TCP)
┌─────────────────▼───────────────────┐
│  Daemon Layer (Dart CLI)            │  ← milestones 1-3 ✅
│  - Device tracking, scrcpy launch   │
│  - Wireless hotspot orchestration   │
└─────────────────┬───────────────────┘
                  │ adb TCP protocol
┌─────────────────▼───────────────────┐
│  Core Layer (Pure Dart library)     │  ← milestones 1-3 ✅
│  - adb client, device models        │
│  - wire protocol, test fakes        │
└─────────────────────────────────────┘
```

Each layer is independent, independently testable, independently deployable.

---

## Known Limitations

1. **No Flutter UI yet** (milestone 5). Daemon runs headless, controlled via terminal commands.
2. **No tray icon** (milestone 5). No system integration yet.
3. **No installer** (milestone 6). Users must download, extract, and run daemon manually.
4. **Bundled binaries not included** (milestone 6). adb and scrcpy must be on PATH or specified in config.json.
5. **Windows only** (for now). Core adb client is portable; daemon and UI are Windows-specific due to scrcpy launcher and tray icon.

---

## Testing

**Run all tests:**
```powershell
cd packages\core
dart test
# Output: 00:00 +21: All tests passed!

cd ..\daemon
dart test test\handoff_test.dart
# Output: 00:00 +0 ~3: All tests skipped. (handoff scaffold, ready for impl)
```

**Manual end-to-end:**
1. Plug phone via USB.
2. `cd packages\daemon && dart run bin\daemon.dart`
3. Observe: `[+] Pixel 10a (serial) connected via USB` + mirror opens.
4. Type `w`, enable hotspot, connect PC, unplug.
5. Observe: `[w] trying 192.168.x.x...` → `[w] connected wirelessly`.

---

## File Checklist

```
voyager/
├── README.md                       ✅ Quick start
├── ARCHITECTURE.md                 ✅ Layers, data flow, design decisions
├── PROJECT_STRUCTURE.md            ✅ Every file explained
├── packages/
│   ├── core/                       ✅ adb client library + 21 tests
│   ├── daemon/                     ✅ device watcher + launcher + wireless
│   ├── ipc/                        ✅ daemon-UI protocol + server/client
│   └── ui/                         ⏳ (milestone 5) will be flutter create
└── vendor/
    ├── adb/                        ⏳ (milestone 6) drop platform-tools here
    └── scrcpy/                     ⏳ (milestone 6) drop scrcpy release here
```

---

## Next Steps (Milestone 4+)

### Milestone 4: Handoff CLI Command (This Week)
- Extract handoff orchestration from test scaffold into `lib/src/handoff.dart`.
- Wire into daemon CLI: type `h` for one-step USB→wireless transition.
- Verify new window opens before old closes (no flicker).

### Milestone 5: Flutter UI + IPC (2-4 Weeks)
- Build Flutter Windows app: tray icon, device popup, settings window.
- Wire daemon-UI communication over IPC (NDJSON over loopback TCP).
- Remove stdin commands, use IPC instead.

### Milestone 6: Installer & Bundling (4-6 Weeks)
- Bundle adb.exe and scrcpy.exe in vendor/.
- Create Windows .exe installer (NSIS or Inno Setup).
- Windows startup integration (registry or Task Scheduler).
- Code signing, Start Menu shortcuts, professional branding.

---

## Development Notes

**Why pure Dart adb client?**
- Reliable: we control the protocol, not dependent on adb CLI format.
- Fast: TCP socket, no subprocess overhead.
- Portable: works anywhere with adb server running.

**Why separate packages?**
- core = reusable library (no platform deps, testable in isolation).
- daemon = headless (can run on server, easy to debug).
- ui = thin dashboard on top of daemon.
- ipc = contracts both sides speak.

**Why hotspot mode is so powerful:**
- No "wireless debugging" toggle (confuses users).
- Works over any tethered connection (hotspot, USB tether, etc.).
- Same code path as same-WiFi mode (just retries gateways).

---

## Contributors

**Babul Raj Singh** — architecture, core adb client, daemon + wireless orchestration, testing, documentation.

---

## License

TBD (add your license here if making public).

---

## Feedback & Issues

Questions? Found a bug? Open an issue (repository TBD).

For development setup, see [README.md](README.md).  
For architecture & design, see [ARCHITECTURE.md](ARCHITECTURE.md).  
For file-by-file guide, see [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).