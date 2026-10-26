import 'package:scrcpy_ipc/scrcpy_ipc.dart';
import 'package:test/test.dart';

void main() {
  group('encodeLine / decodeLine', () {
    test('round-trips one JSON object per line', () {
      final line = encodeLine({'type': 'cmd', 'id': '1'});

      expect(line.endsWith('\n'), isTrue);
      expect('\n'.allMatches(line).length, 1);
      expect(decodeLine(line), {'type': 'cmd', 'id': '1'});
    });

    test('returns null for blank, malformed and non-object lines', () {
      expect(decodeLine(''), isNull);
      expect(decodeLine('   \n'), isNull);
      expect(decodeLine('{not json'), isNull);
      expect(decodeLine('[1, 2]'), isNull);
      expect(decodeLine('"text"'), isNull);
    });
  });

  group('IpcRequest.tryParse', () {
    test('parses a command with arguments', () {
      final request = IpcRequest.tryParse({
        'type': 'cmd',
        'id': '7',
        'cmd': IpcCommands.launch,
        'args': {'serial': 'ABC'},
      });

      expect(request, isNotNull);
      expect(request!.id, '7');
      expect(request.cmd, IpcCommands.launch);
      expect(request.args, {'serial': 'ABC'});
    });

    test('defaults args to empty when absent or not an object', () {
      expect(
        IpcRequest.tryParse({'type': 'cmd', 'id': '1', 'cmd': 'quit'})!.args,
        isEmpty,
      );
      expect(
        IpcRequest.tryParse(
                {'type': 'cmd', 'id': '1', 'cmd': 'quit', 'args': 'oops'})!
            .args,
        isEmpty,
      );
    });

    test('rejects anything that is not a well-formed command', () {
      expect(IpcRequest.tryParse({'type': 'event', 'id': '1', 'cmd': 'x'}),
          isNull);
      expect(IpcRequest.tryParse({'type': 'cmd', 'cmd': 'x'}), isNull);
      expect(IpcRequest.tryParse({'type': 'cmd', 'id': 1, 'cmd': 'x'}), isNull);
      expect(IpcRequest.tryParse({'type': 'cmd', 'id': '1'}), isNull);
      expect(IpcRequest.tryParse({'type': 'cmd', 'id': '1', 'cmd': 5}), isNull);
    });

    test('toJson omits empty args and survives a round trip', () {
      const bare = IpcRequest(id: '1', cmd: 'quit');
      expect(bare.toJson().containsKey('args'), isFalse);

      const withArgs =
          IpcRequest(id: '2', cmd: 'stop', args: {'serial': 'ABC'});
      final parsed = IpcRequest.tryParse(withArgs.toJson())!;
      expect(parsed.cmd, 'stop');
      expect(parsed.args, {'serial': 'ABC'});
    });
  });

  group('IpcResult', () {
    test('success carries data and parses back', () {
      final json = const IpcResult.success('3', {'launched': true}).toJson();
      expect(json, {
        'type': 'result',
        'id': '3',
        'ok': true,
        'data': {'launched': true},
      });

      final parsed = IpcResult.tryParse(json)!;
      expect(parsed.ok, isTrue);
      expect(parsed.data, {'launched': true});
    });

    test('failure carries the error text and parses back', () {
      final json = const IpcResult.failure('4', 'no such device').toJson();
      expect(json['ok'], isFalse);
      expect(json.containsKey('data'), isFalse);

      final parsed = IpcResult.tryParse(json)!;
      expect(parsed.ok, isFalse);
      expect(parsed.error, 'no such device');
    });

    test('a failure without an error field gets a placeholder message', () {
      final parsed =
          IpcResult.tryParse({'type': 'result', 'id': '5', 'ok': false})!;
      expect(parsed.error, 'unknown error');
    });

    test('rejects a result without a string id', () {
      expect(IpcResult.tryParse({'type': 'result', 'ok': true}), isNull);
      expect(
          IpcResult.tryParse({'type': 'result', 'id': 1, 'ok': true}), isNull);
      expect(IpcResult.tryParse({'type': 'cmd', 'id': '1'}), isNull);
    });
  });

  group('IpcEvent', () {
    test('convenience constructors produce the documented payloads', () {
      expect(
        IpcEvent.devices([
          {'serial': 'A', 'state': 'device', 'mirroring': false}
        ]).toJson(),
        {
          'type': 'event',
          'event': IpcEvents.devices,
          'data': {
            'devices': [
              {'serial': 'A', 'state': 'device', 'mirroring': false}
            ]
          },
        },
      );
      expect(IpcEvent.deviceGone('A').data, {'serial': 'A'});
      expect(
          IpcEvent.scrcpyExited('A', 2).data, {'serial': 'A', 'exitCode': 2});
      expect(IpcEvent.log('hello').data, {'message': 'hello'});
    });

    test('status events include detail only when given', () {
      expect(IpcEvent.wirelessStatus('A', 'connecting').data,
          {'serial': 'A', 'stage': 'connecting'});
      expect(IpcEvent.handoffStatus('A', 'failed', 'why').data,
          {'serial': 'A', 'stage': 'failed', 'detail': 'why'});
    });

    test('tryParse round-trips and rejects non-events', () {
      final event = IpcEvent.deviceReady('A', model: 'Pixel 7');
      final parsed = IpcEvent.tryParse(event.toJson())!;
      expect(parsed.event, IpcEvents.deviceReady);
      expect(parsed.data, {'serial': 'A', 'model': 'Pixel 7'});

      expect(IpcEvent.tryParse({'type': 'result', 'event': 'x'}), isNull);
      expect(IpcEvent.tryParse({'type': 'event'}), isNull);
    });
  });
}
