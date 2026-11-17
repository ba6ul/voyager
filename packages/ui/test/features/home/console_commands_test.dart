import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/core/daemon/daemon_launcher.dart';
import 'package:scrcpy_ui/features/devices/domain/entities/device.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/home/presentation/console_commands.dart';

import '../devices/fake_device_repository.dart';

class _Launcher implements DaemonLauncher {
  int starts = 0;
  String? result;

  @override
  Future<String?> start() async {
    starts++;
    return result;
  }
}

const _usb = Device(
    serial: '65261XEA33U4D0',
    state: DeviceState.device,
    model: 'Pixel 10a',
    mirroring: false);
const _net = Device(
    serial: '192.168.43.1:5555',
    state: DeviceState.device,
    model: 'Galaxy S24',
    mirroring: true);

void main() {
  late FakeDeviceRepository repository;
  late DeviceListCubit cubit;
  late _Launcher launcher;
  late List<String> out;
  late ConsoleCommands console;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    repository = FakeDeviceRepository();
    cubit = DeviceListCubit(repository);
    launcher = _Launcher();
    out = [];
    console = ConsoleCommands(cubit, launcher, (l) => out.add(l.text));
    repository.connectedController.add(true);
    repository.devicesController.add(const [_usb, _net]);
    await settle();
  });

  tearDown(() => cubit.close());

  test('devices lists every unit with its link and mirroring', () async {
    await console.run('devices');

    expect(out, [
      '65261XEA33U4D0  device  usb',
      '192.168.43.1:5555  device  network  mirroring',
    ]);
  });

  test('play with no argument uses the first ready unit', () async {
    await console.run('play');

    expect(repository.playedSerials, ['65261XEA33U4D0']);
  });

  test('a unit can be picked by part of its serial or model', () async {
    await console.run('stop 192.168');
    await console.run('wireless pixel');
    await console.run('handoff 6526');

    expect(repository.stoppedSerials, ['192.168.43.1:5555']);
    expect(repository.wirelessSerials, ['65261XEA33U4D0']);
    expect(repository.handoffSerials, ['65261XEA33U4D0']);
  });

  test('an ambiguous or unknown unit sends nothing and says so', () async {
    await console.run('play 5'); // matches both serials
    await console.run('play nokia');

    expect(repository.playedSerials, isEmpty);
    expect(out[0], contains('matches 2 units'));
    expect(out[1], contains("no unit matches 'nokia'"));
  });

  test('usb, stopall and config reach the daemon', () async {
    await console.run('usb 192.168');
    await console.run('stopall');
    await console.run('config');

    expect(repository.usbModeSerials, ['192.168.43.1:5555']);
    expect(repository.stopAllCalls, 1);
    expect(out.join('\n'), contains('"autoLaunch": true'));
  });

  test('a command the daemon rejects reports the reason', () async {
    repository.commandError = 'boom';

    await console.run('stopall');

    expect(out.single, 'stopall failed: boom');
  });

  test('raw adb and shell commands say coming soon; others are unknown',
      () async {
    await console.run('adb devices');
    await console.run('frobnicate');

    expect(out[0], contains('coming soon'));
    expect(out[1], contains("unknown command 'frobnicate'"));
  });

  test('quit asks the daemon to exit', () async {
    await console.run('quit');

    expect(repository.quitCalls, 1);
  });

  test('restart stops the service, starts it again and waits for it',
      () async {
    final done = console.run('restart');
    await settle();
    expect(repository.quitCalls, 1);
    expect(launcher.starts, 0, reason: 'not before the service is gone');

    repository.connectedController.add(false);
    await settle();
    expect(launcher.starts, 1);

    repository.connectedController.add(true);
    await done;

    expect(out.last, 'service is back');
  });

  test('restart reports a failure to start', () async {
    launcher.result = 'no dart';
    final done = console.run('restart');
    await settle();
    repository.connectedController.add(false);

    await done;

    expect(out.last, 'no dart');
  });
}
