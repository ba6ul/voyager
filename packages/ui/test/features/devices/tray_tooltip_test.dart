import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_state.dart';
import 'package:scrcpy_ui/features/devices/presentation/tray_tooltip.dart';

Device _device(String serial,
        {DeviceState state = DeviceState.device, bool mirroring = false}) =>
    Device(serial: serial, state: state, mirroring: mirroring);

DeviceListState _connected(List<Device> devices) =>
    DeviceListState(connection: DaemonConnection.connected, devices: devices);

void main() {
  test('before the daemon has answered it is just the name', () {
    expect(describeTray(const DeviceListState()), 'Voyager');
  });

  test('says when the background service is not running', () {
    expect(
      describeTray(
          const DeviceListState(connection: DaemonConnection.unreachable)),
      'Voyager: background service not running',
    );
  });

  test('says when no phone is connected', () {
    expect(describeTray(_connected([])), 'Voyager: no phone connected');
  });

  test('counts connected and mirroring phones', () {
    expect(
      describeTray(_connected([_device('A', mirroring: true)])),
      'Voyager: 1 phone connected, 1 mirroring',
    );
    expect(
      describeTray(_connected([
        _device('A', mirroring: true),
        _device('B'),
        _device('C', mirroring: true),
      ])),
      'Voyager: 3 phones connected, 2 mirroring',
    );
  });

  test('a phone that is not ready is not counted as connected', () {
    expect(
      describeTray(_connected([_device('A', state: DeviceState.unauthorized)])),
      'Voyager: no phone connected',
    );
    expect(
      describeTray(_connected([
        _device('A', state: DeviceState.offline),
        _device('B'),
      ])),
      'Voyager: 1 phone connected, 0 mirroring',
    );
  });
}
