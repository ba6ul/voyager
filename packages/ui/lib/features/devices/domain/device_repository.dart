import 'entities/cached_device.dart';
import 'entities/device.dart';

/// Progress of an in-flight wireless or handoff operation for one device.
class StatusEvent {
  const StatusEvent({required this.serial, required this.stage, this.detail});

  final String serial;
  final String stage;
  final String? detail;
}

/// What the daemon did with a "Try Now" for a cached device.
enum RetryOutcome {
  /// `adb connect` succeeded; the device shows up in [DeviceRepository.devices]
  /// a moment later.
  reconnected,

  /// Nothing answered at the cached address.
  unreachable,

  /// Not tried: the phone is already connected or a wireless flow is running.
  skipped,

  /// The daemon accepted the request but did not say what happened (a daemon
  /// older than the outcome reply).
  requested,
}

class RetryResult {
  const RetryResult(this.outcome, {this.address});

  final RetryOutcome outcome;

  /// The `ip:port` that was tried, when the daemon says.
  final String? address;
}

/// The UI's view of the daemon: a live device list plus the actions a user
/// can take on a device. Implemented over the IPC protocol
/// (daemon_device_repository.dart); the Cubit only ever depends on this.
abstract class DeviceRepository {
  /// Starts (or resumes) talking to the daemon. Safe to call once; the
  /// underlying connection retries on its own if the daemon isn't up yet.
  Future<void> connect();

  /// Whether the daemon is currently reachable over IPC.
  Stream<bool> get connected;

  /// Full device snapshot, re-emitted whenever it changes.
  Stream<List<Device>> get devices;

  /// Serial of a device the moment it becomes ready (for popup-on-connect).
  Stream<String> get deviceReadySerials;

  Stream<StatusEvent> get wirelessStatus;
  Stream<StatusEvent> get handoffStatus;

  /// Devices that have gone wireless before, whether or not they're
  /// currently reachable.
  Stream<List<CachedDevice>> get knownDevices;

  Future<bool> launch(String serial);
  Future<void> stop(String serial);
  Future<void> goWireless(String serial);
  Future<void> handoff(String serial);
  Future<void> usbMode(String serial);

  /// Fires an immediate reconnect attempt for a cached device, rather than
  /// waiting for the daemon's periodic background retry, and reports what
  /// happened.
  Future<RetryResult> retryReconnect(String usbSerial);

  void dispose();
}
