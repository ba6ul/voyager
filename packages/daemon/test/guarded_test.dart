import 'dart:async';

import 'package:scrcpy_daemon/src/guarded.dart';
import 'package:test/test.dart';

void main() {
  group('guarded', () {
    test('completes normally when the body throws asynchronously', () async {
      final logs = <String>[];

      await guarded(
        'job',
        () async {
          await Future<void>.delayed(Duration.zero);
          throw StateError('boom');
        },
        log: logs.add,
      );

      expect(logs.single, contains('job'));
      expect(logs.single, contains('boom'));
    });

    test('completes normally when the body throws before its first await',
        () async {
      final logs = <String>[];

      await guarded('job', () => throw StateError('sync'), log: logs.add);

      expect(logs.single, contains('sync'));
    });

    test('reports the error to onError exactly once', () async {
      final reported = <Object>[];

      await guarded(
        'job',
        () async => throw ArgumentError('bad'),
        onError: (error, stack) => reported.add(error),
        log: (_) {},
      );

      expect(reported, hasLength(1));
      expect(reported.single, isA<ArgumentError>());
    });

    test('does not log or report anything when the body succeeds', () async {
      final logs = <String>[];
      var reports = 0;
      var ran = false;

      await guarded(
        'job',
        () async => ran = true,
        onError: (_, __) => reports++,
        log: logs.add,
      );

      expect(ran, isTrue);
      expect(reports, 0);
      expect(logs, isEmpty);
    });

    test('an onError that itself throws does not escape', () async {
      final logs = <String>[];

      await guarded(
        'job',
        () async => throw StateError('first'),
        onError: (_, __) => throw StateError('second'),
        log: logs.add,
      );

      expect(logs, hasLength(2));
      expect(logs.last, contains('second'));
    });

    test('an un-awaited call cannot produce an uncaught async error',
        () async {
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        // The shape used at every fire-and-forget site in the daemon.
        unawaited(guarded(
          'job',
          () async => throw StateError('nobody awaits this'),
          log: (_) {},
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (error, stack) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });
  });
}
