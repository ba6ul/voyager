import 'package:equatable/equatable.dart';

import '../../domain/entities/cached_device.dart';
import '../../domain/entities/device.dart';

enum DaemonConnection { initial, unreachable, connected }

/// Progress or outcome of a "Try Now" for one cached device.
class RetryStatus extends Equatable {
  const RetryStatus.trying()
      : inProgress = true,
        message = null;
  const RetryStatus.finished(String this.message) : inProgress = false;

  final bool inProgress;

  /// What happened, shown under the device name. Null while [inProgress].
  final String? message;

  @override
  List<Object?> get props => [inProgress, message];
}

/// A command a user can send for a listed device.
enum DeviceAction { play, stop, goWireless, handoff }

/// The last [DeviceAction] sent for one device: in flight, or what came of
/// it when that is worth telling the user. A command that simply worked
/// leaves no status: its effect shows in the device list itself (Play turns
/// into Stop) or in the wireless/handoff progress line.
class DeviceActionStatus extends Equatable {
  const DeviceActionStatus.inProgress(this.action)
      : inProgress = true,
        message = null;
  const DeviceActionStatus.finished(this.action, String this.message)
      : inProgress = false;

  final DeviceAction action;
  final bool inProgress;

  /// What happened, shown on the device's row. Null while [inProgress].
  final String? message;

  @override
  List<Object?> get props => [action, inProgress, message];
}

/// The latest Go Wireless or Handoff progress for one device, as shown on its
/// row.
class ProgressLine extends Equatable {
  const ProgressLine(this.text, {required this.finished});

  final String text;

  /// Whether the flow has ended (connected, complete, failed, turned away).
  /// A line for a flow still running is kept while its device is briefly
  /// missing from the list (`adb tcpip` restarts the phone's adb, which drops
  /// the USB entry for a moment); a finished one goes with the device.
  final bool finished;

  @override
  List<Object?> get props => [text, finished];
}

class DeviceListState extends Equatable {
  const DeviceListState({
    this.connection = DaemonConnection.initial,
    this.devices = const [],
    this.statusMessages = const {},
    this.knownDevices = const [],
    this.retries = const {},
    this.actions = const {},
  });

  final DaemonConnection connection;
  final List<Device> devices;

  /// Latest wireless/handoff progress line per serial, for inline display.
  final Map<String, ProgressLine> statusMessages;

  /// Devices that have gone wireless before, whether or not they're
  /// currently reachable.
  final List<CachedDevice> knownDevices;

  /// "Try Now" state per cached device, keyed by its USB serial.
  final Map<String, RetryStatus> retries;

  /// Play/Stop/Go Wireless/Handoff in flight or just finished, keyed by the
  /// device's serial. At most one per device: a second is not sent while one
  /// is in flight.
  final Map<String, DeviceActionStatus> actions;

  /// Cached devices whose phone is not currently in [devices] under any of
  /// its serials — i.e. worth showing a "previously connected, try
  /// reconnecting" row for. A phone that is already listed (over USB, its
  /// wireless address, or wireless debugging) must not also get a pending row.
  List<CachedDevice> get pendingReconnect => knownDevices
      .where((c) => !devices.any((d) => c.isRepresentedBy(d.serial)))
      .toList();

  DeviceListState copyWith({
    DaemonConnection? connection,
    List<Device>? devices,
    Map<String, ProgressLine>? statusMessages,
    List<CachedDevice>? knownDevices,
    Map<String, RetryStatus>? retries,
    Map<String, DeviceActionStatus>? actions,
  }) =>
      DeviceListState(
        connection: connection ?? this.connection,
        devices: devices ?? this.devices,
        statusMessages: statusMessages ?? this.statusMessages,
        knownDevices: knownDevices ?? this.knownDevices,
        retries: retries ?? this.retries,
        actions: actions ?? this.actions,
      );

  @override
  List<Object?> get props =>
      [connection, devices, statusMessages, knownDevices, retries, actions];
}
