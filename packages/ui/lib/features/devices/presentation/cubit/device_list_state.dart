import 'package:equatable/equatable.dart';

import '../../domain/entities/device.dart';

enum DaemonConnection { initial, unreachable, connected }

class DeviceListState extends Equatable {
  const DeviceListState({
    this.connection = DaemonConnection.initial,
    this.devices = const [],
    this.statusMessages = const {},
  });

  final DaemonConnection connection;
  final List<Device> devices;

  /// Latest wireless/handoff progress line per serial, for inline display.
  final Map<String, String> statusMessages;

  DeviceListState copyWith({
    DaemonConnection? connection,
    List<Device>? devices,
    Map<String, String>? statusMessages,
  }) =>
      DeviceListState(
        connection: connection ?? this.connection,
        devices: devices ?? this.devices,
        statusMessages: statusMessages ?? this.statusMessages,
      );

  @override
  List<Object?> get props => [connection, devices, statusMessages];
}
