import 'package:equatable/equatable.dart';

import '../../domain/entities/cached_device.dart';
import '../../domain/entities/device.dart';

enum DaemonConnection { initial, unreachable, connected }

class DeviceListState extends Equatable {
  const DeviceListState({
    this.connection = DaemonConnection.initial,
    this.devices = const [],
    this.statusMessages = const {},
    this.knownDevices = const [],
  });

  final DaemonConnection connection;
  final List<Device> devices;

  /// Latest wireless/handoff progress line per serial, for inline display.
  final Map<String, String> statusMessages;

  /// Devices that have gone wireless before, whether or not they're
  /// currently reachable.
  final List<CachedDevice> knownDevices;

  /// Cached devices not currently present in [devices] — i.e. worth showing
  /// a "previously connected, try reconnecting" row for.
  List<CachedDevice> get pendingReconnect => knownDevices
      .where((c) => !devices.any((d) => d.serial == c.networkSerial))
      .toList();

  DeviceListState copyWith({
    DaemonConnection? connection,
    List<Device>? devices,
    Map<String, String>? statusMessages,
    List<CachedDevice>? knownDevices,
  }) =>
      DeviceListState(
        connection: connection ?? this.connection,
        devices: devices ?? this.devices,
        statusMessages: statusMessages ?? this.statusMessages,
        knownDevices: knownDevices ?? this.knownDevices,
      );

  @override
  List<Object?> get props =>
      [connection, devices, statusMessages, knownDevices];
}
