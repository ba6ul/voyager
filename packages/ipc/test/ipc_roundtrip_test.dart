import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scrcpy_ipc/scrcpy_ipc.dart';
import 'package:test/test.dart';

/// Server and client talk over real loopback sockets on an OS-assigned port,
/// so nothing here depends on port 38765 being free.
void main() {
  late IpcServer server;
  final clients = <IpcClient>[];

  Future<IpcClient> connect() async {
    final client = IpcClient();
    await client.connect(port: server.port);
    clients.add(client);
    return client;
  }

  Future<IpcServer> startServer({
    Future<Map<String, dynamic>> Function(IpcRequest request)? onCommand,
    List<IpcEvent> Function()? snapshot,
  }) async {
    final s = IpcServer(
      onCommand: onCommand ?? (request) async => {'echo': request.cmd},
      snapshot: snapshot,
    );
    await s.start(port: 0);
    return s;
  }

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    if (server.isRunning) await server.stop();
  });

  group('commands', () {
    test('a command reaches the handler and its data comes back', () async {
      server = await startServer(onCommand: (request) async {
        return {'cmd': request.cmd, 'serial': request.args['serial']};
      });
      final client = await connect();

      final result = await client.send(IpcCommands.launch, {'serial': 'ABC'});

      expect(result.ok, isTrue);
      expect(result.data, {'cmd': 'launch', 'serial': 'ABC'});
    });

    test('a handler that throws becomes IpcCommandFailed with the message',
        () async {
      server = await startServer(onCommand: (request) async {
        throw 'no such device';
      });
      final client = await connect();

      await expectLater(
        client.send(IpcCommands.stop, {'serial': 'x'}),
        throwsA(isA<IpcCommandFailed>()
            .having((e) => e.message, 'message', 'no such device')),
      );
    });

    test('replies are matched to their request when several are in flight',
        () async {
      final release = Completer<void>();
      server = await startServer(onCommand: (request) async {
        if (request.cmd == 'slow') await release.future;
        return {'cmd': request.cmd};
      });
      final client = await connect();

      final slow = client.send('slow');
      final fast = await client.send('fast');
      expect(fast.data, {'cmd': 'fast'});

      release.complete();
      expect((await slow).data, {'cmd': 'slow'});
    });

    test('send times out when the daemon never answers', () async {
      server = await startServer(
        onCommand: (request) => Completer<Map<String, dynamic>>().future,
      );
      final client = await connect();

      await expectLater(
        client.send('hang', const {}, const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('send before connect throws StateError', () async {
      server = await startServer();
      expect(() => IpcClient().send('x'), throwsStateError);
    });
  });

  group('events', () {
    test('a new client first receives the snapshot events', () async {
      server = await startServer(
          snapshot: () => [
                IpcEvent.devices([
                  {'serial': 'A', 'state': 'device', 'mirroring': false}
                ]),
                IpcEvent.knownDevices(const []),
              ]);
      // A raw socket sees the catch-up lines exactly as written on connect,
      // without racing a client-side event listener.
      final socket = await Socket.connect('127.0.0.1', server.port);
      final lines = StreamIterator(socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()));

      final events = <IpcEvent>[];
      for (var i = 0; i < 2; i++) {
        expect(await lines.moveNext(), isTrue);
        events.add(IpcEvent.tryParse(
            jsonDecode(lines.current) as Map<String, dynamic>)!);
      }

      expect(events.map((e) => e.event),
          [IpcEvents.devices, IpcEvents.knownDevices]);
      expect((events.first.data['devices'] as List).single['serial'], 'A');

      await lines.cancel();
      socket.destroy();
    });

    test('broadcast reaches every connected client', () async {
      server = await startServer();
      final a = await connect();
      final b = await connect();
      final gotA = a.events.firstWhere((e) => e.event == IpcEvents.deviceGone);
      final gotB = b.events.firstWhere((e) => e.event == IpcEvents.deviceGone);
      await _until(() => server.clientCount == 2);

      server.broadcast(IpcEvent.deviceGone('A'));

      expect((await gotA.timeout(const Duration(seconds: 2))).data,
          {'serial': 'A'});
      expect((await gotB.timeout(const Duration(seconds: 2))).data,
          {'serial': 'A'});
    });

    test('broadcast with no clients is harmless', () async {
      server = await startServer();
      expect(() => server.broadcast(IpcEvent.log('nobody listening')),
          returnsNormally);
    });
  });

  group('robustness', () {
    test('a malformed line gets a log event and the connection stays usable',
        () async {
      server = await startServer();
      final socket = await Socket.connect('127.0.0.1', server.port);
      final lines = StreamIterator(socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()));

      socket.write('{this is not json\n');
      expect(await lines.moveNext(), isTrue);
      final log =
          IpcEvent.tryParse(jsonDecode(lines.current) as Map<String, dynamic>)!;
      expect(log.event, IpcEvents.log);
      expect(log.data['message'], contains('malformed'));

      socket.write(encodeLine(const IpcRequest(id: '9', cmd: 'ping').toJson()));
      expect(await lines.moveNext(), isTrue);
      final result = IpcResult.tryParse(
          jsonDecode(lines.current) as Map<String, dynamic>)!;
      expect(result.id, '9');
      expect(result.ok, isTrue);

      await lines.cancel();
      socket.destroy();
    });

    test('a well-formed JSON line that is not a command gets a log event',
        () async {
      server = await startServer();
      final socket = await Socket.connect('127.0.0.1', server.port);
      final lines = StreamIterator(socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()));

      socket.write('{"type":"cmd"}\n');
      expect(await lines.moveNext(), isTrue);
      final log =
          IpcEvent.tryParse(jsonDecode(lines.current) as Map<String, dynamic>)!;
      expect(log.event, IpcEvents.log);
      expect(log.data['message'], contains('not a command'));

      await lines.cancel();
      socket.destroy();
    });

    test('a client that disconnects is dropped', () async {
      server = await startServer();
      final client = await connect();
      await _until(() => server.clientCount == 1);

      await client.close();

      await _until(() => server.clientCount == 0);
    });

    test('a second server on the same port reports DaemonAlreadyRunning',
        () async {
      server = await startServer();
      final other = IpcServer(onCommand: (_) async => {});

      await expectLater(
        other.start(port: server.port),
        throwsA(isA<DaemonAlreadyRunning>()
            .having((e) => e.port, 'port', server.port)),
      );
    });

    test('stopping the server fails pending requests and signals disconnect',
        () async {
      final started = Completer<void>();
      server = await startServer(onCommand: (request) {
        started.complete();
        return Completer<Map<String, dynamic>>().future;
      });
      final client = await connect();

      final pending = client.send('hang');
      // Surface the failure as a value so it is never reported as unhandled.
      final outcome = pending.then<Object?>((r) => r, onError: (Object e) => e);
      await started.future;
      await server.stop();

      expect(await outcome, isA<StateError>());
      await client.onDisconnected.timeout(const Duration(seconds: 2));
      expect(client.isConnected, isFalse);
    });
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within 2 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
