import 'dart:async';
import 'dart:io';

import 'package:scrcpy_daemon/src/scrcpy_launcher.dart';
import 'package:test/test.dart';

/// A scrcpy process that exits only when the test says so, so the order of
/// "kill requested" and "process actually exited" is under the test's control.
class FakeProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  void exitWith(int code) => _exit.complete(code);

  @override
  int get pid => 1;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();
}

void main() {
  late List<FakeProcess> started;
  late List<List<String>> startedArgs;
  late List<(String, int)> exits;
  // What the launcher told its owner, in order, with whether the serial
  // counted as running at that moment: ('started', 'SER1', true).
  late List<(String, String, bool)> notices;
  Completer<void>? startGate;
  Object? startError;

  late ScrcpyLauncher current;
  ScrcpyLauncher newLauncher() => current = ScrcpyLauncher(
        scrcpyPath: 'scrcpy',
        baseArgs: const ['--stay-awake'],
        onExit: (serial, code) => exits.add((serial, code)),
        onStarted: (serial) =>
            notices.add(('started', serial, current.isRunning(serial))),
        onStartFailed: (serial) =>
            notices.add(('startFailed', serial, current.isRunning(serial))),
        processStarter: (exe, args) async {
          startedArgs.add(args);
          await startGate?.future;
          if (startError != null) throw startError!;
          final process = FakeProcess();
          started.add(process);
          return process;
        },
      );

  setUp(() {
    started = [];
    startedArgs = [];
    exits = [];
    notices = [];
    startGate = null;
    startError = null;
  });

  // Lets exit handlers (which run as microtasks) finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('launch', () {
    test('starts scrcpy with the serial, window title and base args', () async {
      final launcher = newLauncher();

      final result = await launcher.launch('SER1', windowTitle: 'Pixel');

      expect(result, LaunchResult.started);
      expect(startedArgs.single,
          ['-s', 'SER1', '--window-title=Pixel', '--stay-awake']);
      expect(launcher.isRunning('SER1'), isTrue);
    });

    test('two concurrent launches for one serial start exactly one process',
        () async {
      // Regression for #16: the slot used to be written only after
      // Process.start finished, so both calls passed the isRunning check and
      // the second overwrote the first, leaving an untracked scrcpy.
      startGate = Completer<void>();
      final launcher = newLauncher();

      final first = launcher.launch('SER1');
      final second = launcher.launch('SER1');
      expect(launcher.isRunning('SER1'), isTrue,
          reason: 'the slot is reserved while the process is still starting');
      startGate!.complete();

      expect(await first, LaunchResult.started);
      expect(await second, LaunchResult.alreadyRunning);
      expect(startedArgs, hasLength(1));
      expect(started, hasLength(1));
    });

    test('launches for different serials do not block each other', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final a = launcher.launch('A');
      final b = launcher.launch('B');
      startGate!.complete();

      expect(await a, LaunchResult.started);
      expect(await b, LaunchResult.started);
      expect(started, hasLength(2));
    });

    test('a failed start releases the slot so a later launch can succeed',
        () async {
      final launcher = newLauncher();
      startError = const ProcessException('scrcpy', [], 'not found');

      await expectLater(launcher.launch('SER1'), throwsA(isA<ProcessException>()));
      expect(launcher.isRunning('SER1'), isFalse);

      startError = null;
      expect(await launcher.launch('SER1'), LaunchResult.started);
      expect(launcher.isRunning('SER1'), isTrue);
    });

    test('reports alreadyRunning, not a failure, while a mirror is running',
        () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');

      expect(await launcher.launch('SER1'), LaunchResult.alreadyRunning);
      expect(started, hasLength(1));
      expect(launcher.isRunning('SER1'), isTrue);
    });

    test('a start that throws is an error, not a LaunchResult', () async {
      final launcher = newLauncher();
      startError = const ProcessException('scrcpy', [], 'not found');

      await expectLater(
          launcher.launch('SER1'), throwsA(isA<ProcessException>()));
    });
  });

  group('exit handling', () {
    test('a mirror that closes on its own is forgotten and reported', () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');

      started.single.exitWith(0);
      await settle();

      expect(launcher.isRunning('SER1'), isFalse);
      expect(exits, [('SER1', 0)]);
    });

    test('stop kills the process and reports its exit once', () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');

      launcher.stop('SER1');
      expect(started.single.killed, isTrue);
      expect(launcher.isRunning('SER1'), isFalse);

      started.single.exitWith(1);
      await settle();

      expect(exits, [('SER1', 1)]);
    });

    test(
        'the old process exiting after stop+launch does not remove the new one',
        () async {
      // Regression for #16: stop() then launch() stored a new process under
      // the same serial; when the old one finally exited, its handler removed
      // the new entry and reported the live mirror as closed.
      final launcher = newLauncher();
      await launcher.launch('SER1');
      final old = started.single;

      launcher.stop('SER1');
      await launcher.launch('SER1');
      final replacement = started.last;
      expect(replacement, isNot(same(old)));

      old.exitWith(1);
      await settle();

      expect(launcher.isRunning('SER1'), isTrue);
      expect(exits, isEmpty,
          reason: 'a superseded process must not report the serial as closed');

      // The replacement is still fully managed: it can be stopped and its own
      // exit is reported.
      launcher.stop('SER1');
      expect(replacement.killed, isTrue);
      replacement.exitWith(0);
      await settle();
      expect(exits, [('SER1', 0)]);
      expect(launcher.isRunning('SER1'), isFalse);
    });

    test('the replacement closing on its own is still reported after the old '
        'one exited', () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');
      final old = started.single;
      launcher.stop('SER1');
      await launcher.launch('SER1');
      final replacement = started.last;

      old.exitWith(1);
      replacement.exitWith(2);
      await settle();

      expect(launcher.isRunning('SER1'), isFalse);
      expect(exits, [('SER1', 2)]);
    });

    test('an exit for one serial does not touch another', () async {
      final launcher = newLauncher();
      await launcher.launch('A');
      await launcher.launch('B');

      started.first.exitWith(0);
      await settle();

      expect(launcher.isRunning('A'), isFalse);
      expect(launcher.isRunning('B'), isTrue);
      expect(exits, [('A', 0)]);
    });
  });

  group('stop while a process is still starting', () {
    test('closes the mirror as soon as it exists', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final launch = launcher.launch('SER1');
      launcher.stop('SER1');
      startGate!.complete();
      await launch;

      expect(started.single.killed, isTrue);
      expect(launcher.isRunning('SER1'), isFalse);

      started.single.exitWith(143);
      await settle();
      expect(exits, [('SER1', 143)]);
    });

    test('a launch requested after that stop keeps the mirror', () async {
      // stop() then launch() while the first start is still pending: the
      // later request wins, so the mirror must not be killed.
      startGate = Completer<void>();
      final launcher = newLauncher();

      final first = launcher.launch('SER1');
      launcher.stop('SER1');
      final second = launcher.launch('SER1');
      startGate!.complete();

      expect(await first, LaunchResult.started);
      expect(await second, LaunchResult.alreadyRunning);
      expect(started.single.killed, isFalse);
      expect(launcher.isRunning('SER1'), isTrue);
    });

    test('stopAll also closes mirrors that are still starting', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final launch = launcher.launch('SER1');
      launcher.stopAll();
      startGate!.complete();
      await launch;

      expect(started.single.killed, isTrue);
      expect(launcher.isRunning('SER1'), isFalse);
    });

    test('does not affect another serial', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final a = launcher.launch('A');
      final b = launcher.launch('B');
      launcher.stop('A');
      startGate!.complete();
      await Future.wait([a, b]);

      expect(launcher.isRunning('A'), isFalse);
      expect(launcher.isRunning('B'), isTrue);
    });

    // #59: the stop request used to outlive a start that failed, and closed
    // the next successful mirror for the phone the moment it started.
    Future<void> failStartWhileStopping(
        ScrcpyLauncher launcher, void Function() stopIt) async {
      startGate = Completer<void>();
      startError = const ProcessException('scrcpy', [], 'not found');

      final failing = launcher.launch('SER1');
      stopIt();
      startGate!.complete();
      await expectLater(failing, throwsA(isA<ProcessException>()));

      startGate = null;
      startError = null;
    }

    test('a stop during a start that fails does not close the next mirror',
        () async {
      final launcher = newLauncher();
      await failStartWhileStopping(launcher, () => launcher.stop('SER1'));

      expect(await launcher.launch('SER1'), LaunchResult.started);

      expect(started.single.killed, isFalse);
      expect(launcher.isRunning('SER1'), isTrue);
      expect(notices.last, ('started', 'SER1', true));
    });

    test('a stopAll during a start that fails does not close the next mirror',
        () async {
      final launcher = newLauncher();
      await failStartWhileStopping(launcher, launcher.stopAll);

      expect(await launcher.launch('SER1'), LaunchResult.started);

      expect(started.single.killed, isFalse);
      expect(launcher.isRunning('SER1'), isTrue);
    });

    test('a stop with nothing starting leaves no trace for the next launch',
        () async {
      final launcher = newLauncher();

      launcher.stop('SER1');
      await launcher.launch('SER1');

      expect(started.single.killed, isFalse);
      expect(launcher.isRunning('SER1'), isTrue);
    });
  });

  // #56: the daemon re-sends its device list from these callbacks, so the
  // UI's Play/Stop follows a launch as it already follows an exit.
  group('start notifications', () {
    test('a successful launch reports started once, already running',
        () async {
      final launcher = newLauncher();

      expect(await launcher.launch('SER1'), LaunchResult.started);

      expect(notices, [('started', 'SER1', true)]);
    });

    test('alreadyRunning reports nothing', () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');
      notices.clear();

      expect(await launcher.launch('SER1'), LaunchResult.alreadyRunning);

      expect(notices, isEmpty);
    });

    test('two concurrent launches report started once', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final a = launcher.launch('SER1');
      final b = launcher.launch('SER1');
      startGate!.complete();
      await Future.wait([a, b]);

      expect(notices, [('started', 'SER1', true)]);
    });

    test('a failed start reports startFailed, no longer running', () async {
      startGate = Completer<void>();
      final launcher = newLauncher();
      startError = const ProcessException('scrcpy', [], 'not found');

      final launch = launcher.launch('SER1');
      // While the start is pending the serial counts as running, which is
      // what a device list built at this moment would say.
      expect(launcher.isRunning('SER1'), isTrue);
      startGate!.complete();
      await expectLater(launch, throwsA(isA<ProcessException>()));

      expect(launcher.isRunning('SER1'), isFalse);
      expect(notices, [('startFailed', 'SER1', false)]);
    });

    test('a process closed by a stop issued while starting reports no start',
        () async {
      startGate = Completer<void>();
      final launcher = newLauncher();

      final launch = launcher.launch('SER1');
      launcher.stop('SER1');
      startGate!.complete();
      await launch;
      started.single.exitWith(143);
      await settle();

      expect(notices, isEmpty);
      expect(exits, [('SER1', 143)], reason: 'the exit still reports it');
    });

    test('stop and exit after a start report the exit only', () async {
      final launcher = newLauncher();
      await launcher.launch('SER1');
      notices.clear();

      launcher.stop('SER1');
      started.single.exitWith(1);
      await settle();

      expect(notices, isEmpty);
      expect(exits, [('SER1', 1)]);
      expect(launcher.isRunning('SER1'), isFalse);
    });
  });

  group('stopAll', () {
    test('kills every mirror and forgets them', () async {
      final launcher = newLauncher();
      await launcher.launch('A');
      await launcher.launch('B');

      launcher.stopAll();

      expect(started.every((p) => p.killed), isTrue);
      expect(launcher.isRunning('A'), isFalse);
      expect(launcher.isRunning('B'), isFalse);
    });
  });
}
