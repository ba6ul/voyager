import 'cubit/device_list_state.dart';

/// The tray icon's tooltip: what is going on, without opening the window.
/// Windows cuts a tooltip at 127 characters; these are far shorter.
String describeTray(DeviceListState state) {
  switch (state.connection) {
    case DaemonConnection.initial:
      return 'Voyager';
    case DaemonConnection.unreachable:
      return 'Voyager: background service not running';
    case DaemonConnection.connected:
      final connected = state.devices.where((d) => d.isReady).length;
      if (connected == 0) return 'Voyager: no phone connected';
      final mirroring =
          state.devices.where((d) => d.isReady && d.mirroring).length;
      final phones = connected == 1 ? '1 phone' : '$connected phones';
      return 'Voyager: $phones connected, $mirroring mirroring';
  }
}
