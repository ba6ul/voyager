/// Core API boundary and transport layer for the scrcpy automation ecosystem.
///
/// This library encapsulates pure Dart implementations of the Android Debug Bridge (ADB)
/// client engine, wire protocol formatters, and data models. It explicitly avoids
/// downstream framework dependencies, remaining fully decoupling from the Flutter engine
/// to ensure uniform utility across CLI daemons, visual interfaces, and isolated test suites.
library scrcpy_core;

export 'src/adb/adb_client.dart';
export 'src/adb/adb_protocol.dart';
export 'src/models/adb_device.dart';
export 'src/testing/fake_server.dart';
