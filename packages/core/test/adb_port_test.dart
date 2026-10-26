import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('AdbClient.parsePort', () {
    test('uses a valid port', () {
      expect(AdbClient.parsePort('5038'), 5038);
      expect(AdbClient.parsePort('1'), 1);
      // Stray whitespace around the number is tolerated.
      expect(AdbClient.parsePort(' 5038 '), 5038);
      expect(AdbClient.parsePort('65535'), 65535);
    });

    test('falls back to 5037 when missing or not a valid port', () {
      expect(AdbClient.parsePort(null), 5037);
      expect(AdbClient.parsePort(''), 5037);
      expect(AdbClient.parsePort('abc'), 5037);
      expect(AdbClient.parsePort('0'), 5037);
      expect(AdbClient.parsePort('-5'), 5037);
      expect(AdbClient.parsePort('65536'), 5037);
      expect(AdbClient.parsePort('50.38'), 5037);
    });
  });

  group('AdbClient port', () {
    test('an explicit port wins over everything else', () {
      expect(AdbClient(port: 12345).port, 12345);
    });

    test('defaults to the environment-derived port', () {
      // Whatever ANDROID_ADB_SERVER_PORT is on this machine, the default must
      // be what defaultPort says, and a valid port.
      expect(AdbClient().port, AdbClient.defaultPort);
      expect(AdbClient.defaultPort, inInclusiveRange(1, 65535));
    });
  });

  group('AdbClient.ensureServerRunning', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('adb_port_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// A stand-in `adb` that records its arguments and exits 0.
    Future<File> recordingAdb(File argsFile) async {
      if (Platform.isWindows) {
        final script = File('${dir.path}\\fakeadb.bat');
        script.writeAsStringSync('@echo %* > "${argsFile.path}"\r\n');
        return script;
      }
      final script = File('${dir.path}/fakeadb.sh');
      script.writeAsStringSync('#!/bin/sh\necho "\$@" > "${argsFile.path}"\n');
      await Process.run('chmod', ['+x', script.path]);
      return script;
    }

    Future<int> unusedPort() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    }

    test('starts the server on the port the client uses, not on 5037',
        () async {
      final argsFile = File('${dir.path}/args.txt');
      final adb = await recordingAdb(argsFile);
      final port = await unusedPort();

      await AdbClient(adbPath: adb.path, port: port).ensureServerRunning();

      expect(argsFile.readAsStringSync().trim(), '-P $port start-server');
    });

    test('does not start anything when a server already answers', () async {
      final server = await FakeAdbServer.start();
      addTearDown(server.close);
      final argsFile = File('${dir.path}/args.txt');
      final adb = await recordingAdb(argsFile);

      await AdbClient(adbPath: adb.path, port: server.port)
          .ensureServerRunning();

      expect(argsFile.existsSync(), isFalse);
    });
  });
}
