import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';

import '../known_devices.dart';

/// Writes the saved addresses somewhere durable.
typedef SavedAddressesWriter = Future<void> Function(
    Map<String, KnownWirelessDevice> devices);

/// Remembers, per phone, the last `ip:port` it was verifiably reached at, so a
/// later reconnect has a current address to try.
///
/// Only a verified connection is recorded: the `ip:port` transport is in
/// `device` state and `ro.serialno` read over that same transport is the
/// phone's identity. An mDNS advert, an `adb connect` reply or a transport
/// that is still settling is never enough, and neither is a Wireless-debugging
/// or USB transport (their serials are not an address).
///
/// Persists through [KnownDevicesStore] (same file, same JSON shape) and
/// publishes each change on [changes].
class SavedWirelessAddresses {
  SavedWirelessAddresses({
    required Map<String, KnownWirelessDevice> initial,
    required this.readSerialNumber,
    required SavedAddressesWriter persist,
    this.verifyTimeout = const Duration(seconds: 5),
  })  : _entries = Map.of(initial),
        _persist = persist;

  /// Loads the saved file and drops entries that are not a phone's USB
  /// identity (an older build keyed one by a Wireless-debugging serial, which
  /// made the same phone appear twice). A cleaned file is written back.
  static Future<SavedWirelessAddresses> load({
    required SerialNumberReader readSerialNumber,
    File? file,
    Duration verifyTimeout = const Duration(seconds: 5),
  }) async {
    final loaded = await KnownDevicesStore.load(file: file);
    final valid = {
      for (final e in loaded.entries)
        if (AdbTransport.of(e.key) == AdbTransport.usb) e.key: e.value,
    };
    final saved = SavedWirelessAddresses(
      initial: valid,
      readSerialNumber: readSerialNumber,
      persist: (devices) => KnownDevicesStore.save(devices, file: file),
      verifyTimeout: verifyTimeout,
    );
    if (valid.length != loaded.length) {
      stderr.writeln('known_wireless_devices.json: dropped '
          '${loaded.length - valid.length} entry/entries not keyed by a USB '
          'serial');
      await saved._persist(valid);
    }
    return saved;
  }

  final SerialNumberReader readSerialNumber;
  final Duration verifyTimeout;
  final SavedAddressesWriter _persist;

  Map<String, KnownWirelessDevice> _entries;
  final _changes = StreamController<Map<String, KnownWirelessDevice>>.broadcast();
  Future<void> _tail = Future.value();

  /// The saved addresses, keyed by the phone's USB serial.
  Map<String, KnownWirelessDevice> get entries => Map.unmodifiable(_entries);

  /// Emits the full set after every change that was written.
  Stream<Map<String, KnownWirelessDevice>> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  /// Records [networkSerial] (`ip:port`) as [identity]'s address, after
  /// confirming that the phone answering there reports that identity.
  /// Returns true if something was written.
  Future<bool> record({
    required String identity,
    required String model,
    required String networkSerial,
  }) =>
      _inOrder(() async {
        final device =
            AdbDevice(serial: networkSerial, state: AdbDeviceState.device);
        if (await _verifiedIdentity(device) != identity) return false;
        return _commit(identity, model, networkSerial);
      });

  /// A network transport reported ready. If it is a phone already saved and
  /// answers as that phone, its address is brought up to date. Anything else
  /// (unknown phone, another phone at the address, no answer) is ignored.
  Future<bool> recordSighting(AdbDevice device) => _inOrder(() async {
        if (!device.isNetwork || !device.isReady) return false;
        final identity = await _verifiedIdentity(device);
        final entry = identity == null ? null : _entries[identity];
        if (entry == null) return false;
        return _commit(identity!, entry.model, device.serial);
      });

  /// The identity read over [device], or null if it cannot be read in time.
  Future<String?> _verifiedIdentity(AdbDevice device) async {
    try {
      return await DeviceIdentity.resolve(
        device,
        readSerialNumber: readSerialNumber,
      ).timeout(verifyTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _commit(
      String identity, String model, String networkSerial) async {
    final split = networkSerial.lastIndexOf(':');
    final port = int.tryParse(networkSerial.substring(split + 1));
    if (split <= 0 || port == null) return false;
    final ip = networkSerial.substring(0, split).replaceAll(RegExp(r'^\[|\]$'), '');

    final current = _entries[identity];
    if (current != null && current.lastIp == ip && current.lastPort == port) {
      return false;
    }
    final updated = {
      ..._entries,
      identity: KnownWirelessDevice(
        usbSerial: identity,
        model: model,
        lastIp: ip,
        lastPort: port,
      ),
    };
    await _persist(updated);
    _entries = updated;
    if (!_changes.isClosed) _changes.add(entries);
    return true;
  }

  /// Runs [action] after every earlier one, so two sightings of the same phone
  /// (say Go Wireless finishing as track-devices reports it) cannot both pass
  /// the "unchanged" check and write twice.
  Future<bool> _inOrder(Future<bool> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
