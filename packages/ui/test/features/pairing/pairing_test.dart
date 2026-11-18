import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/pairing/presentation/cubit/pairing_cubit.dart';
import 'package:scrcpy_ui/features/pairing/presentation/pairing_text.dart';
import 'package:scrcpy_ui/features/pairing/presentation/widgets/pair_dialog.dart';

import '../devices/fake_device_repository.dart';

void main() {
  group('input checks', () {
    test('address', () {
      expect(addressError('192.168.1.8:37123'), isNull);
      expect(addressError(' 192.168.1.8:37123 '), isNull);
      expect(addressError('192.168.1.8'), isNotNull);
      expect(addressError('abc:1'), isNotNull);
      expect(addressError('192.168.1.300:5'), isNotNull);
      expect(addressError('192.168.1.8:0'), isNotNull);
      expect(addressError('192.168.1.8:70000'), isNotNull);
    });

    test('code', () {
      expect(codeError('123456'), isNull);
      expect(codeError('12345'), isNotNull);
      expect(codeError('12345a'), isNotNull);
    });
  });

  group('describePairing', () {
    String say(String stage, [String? detail]) =>
        describePairing(PairingStatus(stage: stage, detail: detail));

    test('each stage reads as a sentence, with no stage name', () {
      expect(say('pairing'), contains('Pairing'));
      expect(say('wrongCode'), contains('did not accept that code'));
      expect(say('unreachable'), contains('same Wi-Fi'));
      expect(say('pairedOnly'), contains('Wireless debugging is still on'));
      expect(say('connected', '192.168.1.8:40001'), contains('192.168.1.8:40001'));
      expect(say('failed', 'boom'), 'Pairing failed: boom');
    });

    test('an unknown stage still reads as progress', () {
      expect(say('newStage', 'x'), 'Pairing: newStage (x)…');
      expect(isFinalPairingStage('newStage'), isFalse);
    });
  });

  group('PairingCubit', () {
    late FakeDeviceRepository repository;
    late PairingCubit cubit;

    setUp(() {
      repository = FakeDeviceRepository();
      cubit = PairingCubit(repository);
    });

    tearDown(() => cubit.close());

    test('bad input fails at once and sends nothing', () async {
      await cubit.pair('nope', '123456');
      expect(cubit.state.phase, PairingPhase.failed);
      expect(repository.pairCalls, isEmpty);

      await cubit.pair('192.168.1.8:37123', '12');
      expect(cubit.state.message, 'The pairing code is 6 digits.');
      expect(repository.pairCalls, isEmpty);
    });

    test('follows the daemon from working to succeeded', () async {
      await cubit.pair(' 192.168.1.8:37123 ', '123456');
      expect(repository.pairCalls.single.address, '192.168.1.8:37123');
      expect(cubit.state.phase, PairingPhase.working);

      repository.pairingStatusController
          .add(const PairingStatus(stage: 'searching'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, PairingPhase.working);
      expect(cubit.state.message, contains('Looking for the phone'));

      repository.pairingStatusController.add(
          const PairingStatus(stage: 'connected', detail: '192.168.1.8:40001'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, PairingPhase.succeeded);
    });

    test('a wrong code ends as failed with the explanation', () async {
      await cubit.pair('192.168.1.8:37123', '000000');
      repository.pairingStatusController
          .add(const PairingStatus(stage: 'wrongCode'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, PairingPhase.failed);
      expect(cubit.state.message, contains('did not accept that code'));
    });

    test('a request the daemon turns down is shown, not thrown', () async {
      repository.commandError =
          const DaemonCommandException(DaemonCommandFailure.rejected, 'busy');
      await cubit.pair('192.168.1.8:37123', '123456');

      expect(cubit.state.phase, PairingPhase.failed);
      expect(cubit.state.message, 'Could not start pairing: busy');
    });

    test('status events from elsewhere are ignored while editing', () async {
      repository.pairingStatusController
          .add(const PairingStatus(stage: 'connected'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.phase, PairingPhase.editing);
    });
  });

  group('PairDialog', () {
    Future<FakeDeviceRepository> open(WidgetTester tester) async {
      final repository = FakeDeviceRepository();
      await tester.pumpWidget(MaterialApp(
        home: RepositoryProvider<DeviceRepository>.value(
          value: repository,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPairDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('shows the steps and refuses a bad code without sending',
        (tester) async {
      final repository = await open(tester);
      expect(find.textContaining('Wireless debugging'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextField, 'Address (ip:port)'),
          '192.168.1.8:37123');
      await tester.enterText(find.widgetWithText(TextField, 'Pairing code'), '12');
      await tester.tap(find.text('Pair'));
      await tester.pump();

      expect(find.text('The pairing code is 6 digits.'), findsOneWidget);
      expect(repository.pairCalls, isEmpty);
    });

    testWidgets('sends the address and code, then shows the result',
        (tester) async {
      final repository = await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Address (ip:port)'),
          '192.168.1.8:37123');
      await tester.enterText(
          find.widgetWithText(TextField, 'Pairing code'), '123456');
      await tester.tap(find.text('Pair'));
      await tester.pump();

      expect(repository.pairCalls.single.code, '123456');
      repository.pairingStatusController.add(
          const PairingStatus(stage: 'connected', detail: '192.168.1.8:40001'));
      await tester.pump();

      expect(find.textContaining('Paired and connected'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
