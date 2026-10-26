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

class DeviceListState extends Equatable {
  const DeviceListState({
    this.connection = DaemonConnection.initial,
    this.devices = const [],
    this.statusMessages = const {},
    this.knownDevices = const [],
    this.retries = const {},
  });

  final DaemonConnection connection;
  final List<Device> devices;

  /// Latest wireless/handoff progress line per serial, for inline display.
  final Map<String, String> statusMessages;

  /// Devices that have gone wireless before, whether or not they're
  /// currently reachable.
  final List<CachedDevice> knownDevices;

  /// "Try Now" state per cached device, keyed by its USB serial.
  final Map<String, RetryStatus> retries;

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
    Map<String, String>? statusMessages,
    List<CachedDevice>? knownDevices,
    Map<String, RetryStatus>? retries,
  }) =>
      DeviceListState(
        connection: connection ?? this.connection,
        devices: devices ?? this.devices,
        statusMessages: statusMessages ?? this.statusMessages,
        knownDevices: knownDevices ?? this.knownDevices,
        retries: retries ?? this.retries,
      );

  @override
  List<Object?> get props =>
      [connection, devices, statusMessages, knownDevices, retries];
}
