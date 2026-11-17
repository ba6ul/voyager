import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';
import 'package:scrcpy_daemon/src/known_devices.dart';
import 'package:scrcpy_daemon/src/saved_wireless/saved_wireless_addresses.dart';
import 'package:test/test.dart';

const _phone = '65261XEA33U4D0';
const _mdns = 'adb-$_phone-HvLNB1._adb-tls-connect._tcp';

KnownWirelessDevice _entry(String ip, [int port = 5555]) => KnownWirelessDevice(
    usbSerial: _phone, model: 'Pixel 10a', lastIp: ip, lastPort: port);

AdbDevice _ready(String serial) =>
    AdbDevice(serial: serial, state: AdbDeviceState.device);

void main() {
  late Map<String, KnownWirelessDevice> written;
  late int writes;
  late Map<String, String?> serialNumbers; // adb serial -> ro.serialno

  SavedWirelessAddresses make(Map<String, KnownWirelessDevice> initial) {
    return SavedWirelessAddresses(
      initial: initial,
      readSerialNumber: (serial) async {
        if (!serialNumbers.containsKey(serial)) throw 'no answer';
        return serialNumbers[serial];
      },
      persist: (devices) async {
        writes++;
        written = Map.of(devices);
      },
      verifyTimeout: const Duration(seconds: 1),
    );
  }

  Future<bool> record(SavedWirelessAddresses saved, String networkSerial) =>
      saved.record(
          identity: _phone, model: 'Pixel 10a', networkSerial: networkSerial);

  setUp(() {
    written = {};
    writes = 0;
    serialNumbers = {};
  });

  group('record', () {
    test('saves an address whose phone reports the identity', () async {
      serialNumbers['192.168.1.8:5555'] = _phone;
      final saved = make({});

      expect(await record(saved, '192.168.1.8:5555'), isTrue);

      expect(written[_phone]!.networkSerial, '192.168.1.8:5555');
      expect(saved.entries[_phone]!.model, 'Pixel 10a');
    });

    test('writes nothing when another phone answers at the address', () async {
      serialNumbers['192.168.1.8:5555'] = 'SOMEONEELSE';
      final saved = make({});

      expect(await record(saved, '192.168.1.8:5555'), isFalse);
      expect(writes, 0);
    });

    test('writes nothing when the identity cannot be read', () async {
      final saved = make({}); // the reader throws
      expect(await record(saved, '192.168.1.8:5555'), isFalse);
      expect(writes, 0);
    });

    test('writes nothing when the reader hangs past the timeout', () async {
      final saved = SavedWirelessAddresses(
        initial: {},
        readSerialNumber: (_) => Completer<String?>().future,
        persist: (d) async => writes++,
        verifyTimeout: const Duration(milliseconds: 50),
      );
      expect(await record(saved, '192.168.1.8:5555'), isFalse);
      expect(writes, 0);
    });

    test('never saves a USB or Wireless-debugging serial as an address',
        () async {
      serialNumbers[_mdns] = _phone;
      serialNumbers[_phone] = _phone;
      final saved = make({});

      expect(await record(saved, _mdns), isFalse);
      expect(await record(saved, _phone), isFalse);
      expect(writes, 0);
    });

    test('is idempotent: the same address writes and announces nothing',
        () async {
      serialNumbers['192.168.1.8:5555'] = _phone;
      final saved = make({_phone: _entry('192.168.1.8')});
      final events = <Object>[];
      saved.changes.listen(events.add);

      expect(await record(saved, '192.168.1.8:5555'), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(writes, 0);
      expect(events, isEmpty);
    });

    test('announces a change after writing it', () async {
      serialNumbers['192.168.1.8:5555'] = _phone;
      final saved = make({});
      final events = <Map<String, KnownWirelessDevice>>[];
      saved.changes.listen(events.add);

      await record(saved, '192.168.1.8:5555');
      await Future<void>.delayed(Duration.zero);

      expect(events.single[_phone]!.lastIp, '192.168.1.8');
    });

    test('a failed write changes nothing in memory', () async {
      final saved = SavedWirelessAddresses(
        initial: {},
        readSerialNumber: (s) async => _phone,
        persist: (_) async => throw 'disk full',
      );

      await expectLater(record(saved, '192.168.1.8:5555'), throwsA('disk full'));
      expect(saved.entries, isEmpty);
    });

    test('two simultaneous records of one address write once', () async {
      serialNumbers['192.168.1.8:5555'] = _phone;
      final saved = make({});

      await Future.wait([
        record(saved, '192.168.1.8:5555'),
        record(saved, '192.168.1.8:5555'),
      ]);

      expect(writes, 1);
    });
  });

  group('recordSighting', () {
    test('updates a known phone that is ready at a new address', () async {
      serialNumbers['192.168.1.20:5555'] = _phone;
      final saved = make({_phone: _entry('192.168.1.6')});

      expect(await saved.recordSighting(_ready('192.168.1.20:5555')), isTrue);
      expect(written[_phone]!.networkSerial, '192.168.1.20:5555');
    });

    test('seeing the phone at its saved address writes nothing', () async {
      serialNumbers['192.168.1.6:5555'] = _phone;
      final saved = make({_phone: _entry('192.168.1.6')});

      expect(await saved.recordSighting(_ready('192.168.1.6:5555')), isFalse);
      expect(writes, 0);
    });

    test('ignores a phone that was never saved', () async {
      serialNumbers['192.168.1.20:5555'] = 'STRANGER';
      final saved = make({_phone: _entry('192.168.1.6')});

      expect(await saved.recordSighting(_ready('192.168.1.20:5555')), isFalse);
      expect(writes, 0);
    });

    test('ignores a transport that is not in device state', () async {
      serialNumbers['192.168.1.20:5555'] = _phone;
      final saved = make({_phone: _entry('192.168.1.6')});

      expect(
          await saved.recordSighting(const AdbDevice(
              serial: '192.168.1.20:5555', state: AdbDeviceState.offline)),
          isFalse);
      expect(writes, 0);
    });

    test('USB and Wireless-debugging sightings never overwrite the address',
        () async {
      final saved = make({_phone: _entry('192.168.1.6')});

      expect(await saved.recordSighting(_ready(_phone)), isFalse);
      expect(await saved.recordSighting(_ready(_mdns)), isFalse);
      expect(writes, 0);
      expect(saved.entries[_phone]!.lastIp, '192.168.1.6');
    });
  });

  group('load', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('saved_wireless'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('drops an entry keyed by a Wireless-debugging serial and rewrites',
        () async {
      final file = File('${dir.path}/known.json');
      await KnownDevicesStore.save({
        _phone: _entry('192.168.1.8'),
        _mdns: const KnownWirelessDevice(
            usbSerial: _mdns,
            model: 'Pixel 10a',
            lastIp: '192.168.1.8',
            lastPort: 5555),
      }, file: file);

      final saved = await SavedWirelessAddresses.load(
          readSerialNumber: (_) async => _phone, file: file);

      expect(saved.entries.keys, [_phone]);
      expect((await KnownDevicesStore.load(file: file)).keys, [_phone]);
    });

    test('leaves a clean file untouched', () async {
      final file = File('${dir.path}/known.json');
      await KnownDevicesStore.save({_phone: _entry('192.168.1.8')}, file: file);
      final before = file.lastModifiedSync();

      final saved = await SavedWirelessAddresses.load(
          readSerialNumber: (_) async => _phone, file: file);

      expect(saved.entries[_phone]!.lastIp, '192.168.1.8');
      expect(file.lastModifiedSync(), before);
    });
  });
}
