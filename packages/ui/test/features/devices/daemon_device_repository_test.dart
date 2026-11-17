import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ipc/scrcpy_ipc.dart';
import 'package:scrcpy_ui/core/ipc/ipc_connection.dart';
import 'package:scrcpy_ui/features/devices/data/daemon_device_repository.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';

/// Answers [send] the way a test says, without a socket or a daemon.
class _FakeConnection extends IpcConnection {
  /// The reply data for the next command, or how it fails.
  Map<String, dynamic> reply = const {};
  Object? asyncError;

  /// Thrown before any future exists, like the real [IpcConnection.send]
  /// when it is not connected.
  Object? syncError;

  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Future<IpcResult> send(String cmd, [Map<String, dynamic> args = const {}]) {
    sent.add((cmd, args));
    if (syncError != null) throw syncError!;
    if (asyncError != null) return Future.error(asyncError!);
    return Future.value(IpcResult.success('1', reply));
  }
}

void main() {
  late _FakeConnection connection;
  late DaemonDeviceRepository repository;

  setUp(() {
    connection = _FakeConnection();
    repository = DaemonDeviceRepository(connection);
  });

  Matcher failsWith(DaemonCommandFailure failure, {String? detail}) => throwsA(
        isA<DaemonCommandException>()
            .having((e) => e.failure, 'failure', failure)
            .having((e) => e.detail, 'detail', detail),
      );

  group('pair', () {
    test('sends the address and code as the pair command', () async {
      await repository.pair(address: '192.168.1.8:37123', code: '123456');

      final (cmd, args) = connection.sent.single;
      expect(cmd, IpcCommands.pair);
      expect(args, {'address': '192.168.1.8:37123', 'code': '123456'});
    });

    test('a request the daemon rejects is a rejected failure', () async {
      connection.asyncError = IpcCommandFailed(
          IpcCommands.pair, 'the pairing code is 6 digits');

      await expectLater(
          repository.pair(address: '192.168.1.8:37123', code: '1'),
          failsWith(DaemonCommandFailure.rejected,
              detail: 'the pairing code is 6 digits'));
    });
  });

  group('launch', () {
    test('a started mirror is started', () async {
      connection.reply = {'launched': true, 'alreadyRunning': false};

      expect(await repository.launch('SER1'), LaunchOutcome.started);
      final (cmd, args) = connection.sent.single;
      expect(cmd, IpcCommands.launch);
      expect(args, {'serial': 'SER1'});
    });

    test('a running mirror is alreadyRunning, not a failure', () async {
      connection.reply = {'launched': false, 'alreadyRunning': true};

      expect(await repository.launch('SER1'), LaunchOutcome.alreadyRunning);
    });

    test('a reply without alreadyRunning (older daemon) is started', () async {
      connection.reply = {'launched': true};

      expect(await repository.launch('SER1'), LaunchOutcome.started);
    });
  });

  group('a command the daemon cannot carry out', () {
    // Every command goes through the same mapping; each kind of failure is
    // checked on every command that the device rows send.
    final commands = <String, Future<Object?> Function(DeviceRepository)>{
      'launch': (r) => r.launch('SER1'),
      'stop': (r) => r.stop('SER1'),
      'goWireless': (r) => r.goWireless('SER1'),
      'handoff': (r) => r.handoff('SER1'),
      'retryReconnect': (r) => r.retryReconnect('SER1'),
    };

    commands.forEach((name, command) {
      test('$name: a failure reply is rejected, with its first line',
          () async {
        connection.asyncError = IpcCommandFailed(name,
            'ProcessException: file not found\n  Command: scrcpy -s SER1');

        await expectLater(
          command(repository),
          failsWith(DaemonCommandFailure.rejected,
              detail: 'ProcessException: file not found'),
        );
      });

      test('$name: no reply in time is timedOut', () async {
        connection.asyncError = TimeoutException('no reply');

        await expectLater(
            command(repository), failsWith(DaemonCommandFailure.timedOut));
      });

      test('$name: not connected is disconnected, as a future error',
          () async {
        connection.syncError = StateError('not connected to the daemon');

        // Calling it must not throw synchronously: the row callbacks do not
        // await, so only a future error can be handled by the caller.
        late Future<Object?> result;
        expect(() => result = command(repository), returnsNormally);
        await expectLater(result, failsWith(DaemonCommandFailure.disconnected));
      });

      test('$name: a connection lost mid-command is disconnected', () async {
        connection.asyncError = StateError('Connection to daemon lost');

        await expectLater(
            command(repository), failsWith(DaemonCommandFailure.disconnected));
      });
    });
  });

  test('DaemonCommandException reads as a short reason', () {
    expect(
      const DaemonCommandException(DaemonCommandFailure.rejected, 'no scrcpy')
          .toString(),
      'no scrcpy',
    );
    expect(const DaemonCommandException(DaemonCommandFailure.timedOut).toString(),
        'the background service did not answer in time');
    expect(
        const DaemonCommandException(DaemonCommandFailure.disconnected)
            .toString(),
        'not connected to the background service');
  });
}
