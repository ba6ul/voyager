import '../../domain/entities/cached_device.dart';

/// Parses one entry of the `knownDevices` IPC event payload
/// (`{usbSerial, model, lastIp, lastPort}`) into a domain [CachedDevice].
CachedDevice cachedDeviceFromJson(Map<String, dynamic> json) => CachedDevice(
      usbSerial: json['usbSerial'] as String,
      model: json['model'] as String,
      lastIp: json['lastIp'] as String,
      lastPort: json['lastPort'] as int,
    );
