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

/// Progress or result of a Wireless debugging pairing, as the daemon reports
/// it (see `IpcEvents.pairingStatus`).
class PairingStatus {
  const PairingStatus({required this.stage, this.detail});

  /// pairing, searching, connected, pairedOnly, wrongCode, unreachable or
  /// failed. A stage this UI does not know (a newer daemon) is shown as
  /// progress.
  final String stage;
  final String? detail;
}

/// What the daemon did with a Play.
enum LaunchOutcome {
  /// A new scrcpy process was started.
  started,

  /// A mirror for the device was already running (or being started).
  alreadyRunning,
}

/// Why a command to the daemon did not go through.
enum DaemonCommandFailure {
  /// The daemon answered that the command failed; [DaemonCommandException.detail]
  /// says why.
  rejected,

  /// No answer within the IPC timeout.
  timedOut,

  /// Not connected to the daemon, or the connection dropped mid-command.
  disconnected,
}

/// Thrown by every [DeviceRepository] command when the daemon could not carry
/// it out. Its [toString] is a short, readable reason for the UI.
class DaemonCommandException implements Exception {
  const DaemonCommandException(this.failure, [this.detail]);

  final DaemonCommandFailure failure;

  /// The daemon's own error text, for [DaemonCommandFailure.rejected].
  final String? detail;

  @override
  String toString() => switch (failure) {
        DaemonCommandFailure.rejected =>
          detail ?? 'the background service turned the request down',
        DaemonCommandFailure.timedOut =>
          'the background service did not answer in time',
        DaemonCommandFailure.disconnected =>
          'not connected to the background service',
      };
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
///
/// Every command throws [DaemonCommandException] when the daemon cannot carry
/// it out, never a transport-specific error.
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

  /// Progress and result of [pair].
  Stream<PairingStatus> get pairingStatus;

  /// Starts pairing with the phone's Wireless debugging dialog: [address] is
  /// the `ip:port` and [code] the 6 digits it shows. Returns once the daemon
  /// has accepted the request; progress and the result come through
  /// [pairingStatus]. Throws [DaemonCommandException] if it was turned down
  /// (malformed input, a pairing already running).
  Future<void> pair({required String address, required String code});

  Future<LaunchOutcome> launch(String serial);
  Future<void> stop(String serial);

  /// Asks the daemon to start Go Wireless. A request it turns away (another
  /// operation is running, or the device is not on USB) is not an error: the
  /// daemon reports the reason through [wirelessStatus].
  Future<void> goWireless(String serial);

  /// Like [goWireless], reported through [handoffStatus].
  Future<void> handoff(String serial);
  Future<void> usbMode(String serial);

  /// Fires an immediate reconnect attempt for a cached device, rather than
  /// waiting for the daemon's periodic background retry, and reports what
  /// happened.
  Future<RetryResult> retryReconnect(String usbSerial);

  /// Closes every mirror window the daemon has open.
  Future<void> stopAll();

  /// The daemon's current config.json contents.
  Future<Map<String, dynamic>> config();

  /// Shuts the daemon down (it closes every mirror first). The reply comes
  /// before it exits; the connection then drops.
  Future<void> quit();

  void dispose();
}
