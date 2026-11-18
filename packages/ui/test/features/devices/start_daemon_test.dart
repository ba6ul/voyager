import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/core/daemon/daemon_launcher.dart';
import 'package:scrcpy_ui/features/devices/presentation/cubit/device_list_cubit.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/device_list.dart';

import 'fake_device_repository.dart';

class _FakeLauncher implements DaemonLauncher {
  _FakeLauncher(this.result);
  final String? result;
  int starts = 0;

  @override
  Future<String?> start() async {
    starts++;
    return result;
  }
}

void main() {
  late FakeDeviceRepository repository;

  Future<void> show(WidgetTester tester, DaemonLauncher? launcher,
      {bool reachable = false}) async {
    repository = FakeDeviceRepository();
    final cubit = DeviceListCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: DeviceList(daemonLauncher: launcher),
      ),
    ));
    repository.connectedController.add(reachable);
    await tester.pump();
  }

  testWidgets('no button without a launcher', (tester) async {
    await show(tester, null);

    expect(find.text('Start service'), findsNothing);
  });

  testWidgets('no button while the daemon is reachable', (tester) async {
    await show(tester, _FakeLauncher(null), reachable: true);

    expect(find.text('Start service'), findsNothing);
  });

  testWidgets('a failure to start is explained and the button stays usable',
      (tester) async {
    final launcher = _FakeLauncher('Could not find the daemon folder.');
    await show(tester, launcher);

    await tester.tap(find.text('Start service'));
    await tester.pump();

    expect(launcher.starts, 1);
    expect(find.text('Could not find the daemon folder.'), findsOneWidget);
    expect(find.text('Start service'), findsOneWidget);
  });

  testWidgets('a started daemon disables the button while waiting for it',
      (tester) async {
    final launcher = _FakeLauncher(null);
    await show(tester, launcher);

    await tester.tap(find.text('Start service'));
    await tester.pump();

    expect(find.text('Starting...'), findsOneWidget);
    // A second tap sends nothing.
    await tester.tap(find.text('Starting...'), warnIfMissed: false);
    await tester.pump();
    expect(launcher.starts, 1);

    // Never answered: it says so and offers a retry.
    await tester.pump(const Duration(seconds: 21));
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(find.text('Start service'), findsOneWidget);
  });
}
