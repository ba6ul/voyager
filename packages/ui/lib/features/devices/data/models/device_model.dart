import '../../domain/entities/device.dart';

/// Parses one entry of the `devices` IPC event payload
/// (`{serial, state, transport?, model?, mirroring}`) into a domain [Device].
Device deviceFromJson(Map<String, dynamic> json) => Device(
      serial: json['serial'] as String,
      state: DeviceState.parse(json['state'] as String),
      model: json['model'] as String?,
      mirroring: json['mirroring'] as bool? ?? false,
      // Absent from an older daemon: the Device then works it out itself.
      transport: DeviceTransport.parse(json['transport']),
    );
