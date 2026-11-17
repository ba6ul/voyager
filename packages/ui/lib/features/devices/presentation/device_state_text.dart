import '../domain/entities/device.dart';

/// What to show for a device that is not ready: a short [label] in place of
/// the raw adb state, and a [hint] saying what the user can do (null when
/// there is nothing they can do).
class DeviceStateText {
  const DeviceStateText(this.label, [this.hint]);

  final String label;
  final String? hint;
}

DeviceStateText describeDeviceState(DeviceState state) {
  switch (state) {
    case DeviceState.device:
      return const DeviceStateText('Ready');
    case DeviceState.unauthorized:
      return const DeviceStateText(
        'Waiting for permission',
        'Look at the phone and tap Allow on the "Allow USB debugging?" prompt.',
      );
    case DeviceState.offline:
      return const DeviceStateText(
        'Not responding',
        'Unplug the cable and plug it in again. If it stays like this, '
            'turn USB debugging off and on in the phone\'s Developer options.',
      );
    case DeviceState.recovery:
      return const DeviceStateText(
        'In recovery mode',
        'Restart the phone normally to use it with Voyager.',
      );
    case DeviceState.bootloader:
      return const DeviceStateText(
        'In bootloader mode',
        'Restart the phone normally to use it with Voyager.',
      );
    case DeviceState.unknown:
      return const DeviceStateText(
        'Not ready',
        'Wait a few seconds. If it stays like this, plug the cable in again.',
      );
  }
}

/// Texts for the window's non-device states.
const connectingText = 'Connecting to the Voyager background service...';
const unreachableTitle = 'Voyager\'s background service is not running';
const unreachableHint =
    'Close Voyager and open it again. If this keeps happening, restart your PC.';
const noDevicesTitle = 'No phone connected';
const noDevicesHint =
    'Turn on USB debugging on your phone (Settings > Developer options), '
    'then connect it with a USB cable.';
