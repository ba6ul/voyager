import 'dart:async';
import 'dart:io';

import 'package:scrcpy_core/scrcpy_core.dart';

import 'guarded.dart';

/// Turns the adb `track-devices` snapshots into per-device events: attached,
/// state changes, became ready, gone.
///
/// A snapshot is handled synchronously. What happens when a device becomes
/// ready (reading its model name, then [onReady]) runs as a separate guarded
/// task, so a slow or failing adb call for one device can neither hold up the
/// next snapshot for every other device nor end up as an error of the
/// tracking stream.
class DeviceTracker {
  DeviceTracker({
    required this.client,
    required this.modelNames,
    required this.onReady,
    this.onGone,
    this.onChanged,
    this.modelTimeout = const Duration(seconds: 5),
    void Function(String message)? log,
  }) : _log = log ?? ((message) => stdout.writeln(message));

  final AdbClient client;

  /// Model names read so far, keyed by serial. Shared with the caller; only
  /// real names are stored (a lookup that failed leaves no entry).
  final Map<String, String> modelNames;

  /// Called once a device is ready, with its model name, or its serial when
  /// the name could not be read in time. Runs off the tracking path.
  final Future<void> Function(AdbDevice device, String name) onReady;

  /// Called when a device has disappeared from the snapshot.
  final void Function(String serial)? onGone;

  /// Called after every snapshot with the new device map.
  final void Function(Map<String, AdbDevice> known)? onChanged;

  /// How long to wait for the device's model name. The device is announced
  /// under its serial if it does not answer.
  final Duration modelTimeout;

  final void Function(String message) _log;

  Map<String, AdbDevice> _known = const {};

  /// The devices from the latest snapshot.
  Map<String, AdbDevice> get known => _known;

  void handleSnapshot(List<AdbDevice> snapshot) {
    final current = {for (final d in snapshot) d.serial: d};

    for (final device in current.values) {
      final previous = _known[device.serial];
      if (previous == null) {
        _logAttached(device);
      } else if (previous.state != device.state) {
        _log('[~] ${device.serial}: '
            '${previous.state.name} -> ${device.state.name}');
      }
      final becameReady =
          device.isReady && (previous == null || !previous.isReady);
      if (becameReady) _announceWhenReady(device);
    }
    for (final serial in _known.keys) {
      if (!current.containsKey(serial)) {
        _log('[-] $serial disconnected');
        onGone?.call(serial);
      }
    }
    _known = current;
    onChanged?.call(_known);
  }

  void _announceWhenReady(AdbDevice device) {
    unawaited(guarded(
      'ready handling for ${device.serial}',
      () async {
        final model = await _readModel(device.serial);
        // It may have been unplugged while we waited for the name.
        if (_known[device.serial]?.isReady != true) return;
        if (model != null) modelNames[device.serial] = model;
        await onReady(device, model ?? device.serial);
      },
      log: _log,
    ));
  }

  /// The model name, or null if the device does not answer within
  /// [modelTimeout] or the lookup fails (for example it was unplugged between
  /// the snapshot and the call). A lookup that merely timed out keeps running;
  /// if it answers later the name is filled in (see [_adoptLateModel]).
  Future<String?> _readModel(String serial) async {
    final lookup = client.model(serial);
    try {
      return await lookup.timeout(modelTimeout);
    } catch (e) {
      _log('[?] could not read the model of $serial ($e); using the serial');
      _adoptLateModel(serial, lookup);
      return null;
    }
  }

  /// A device slower than [modelTimeout] was announced under its serial. When
  /// its answer finally arrives, remember it and tell [onChanged] so the name
  /// shown to users catches up. Ignored if the device is gone by then, or the
  /// lookup failed (nothing to adopt).
  void _adoptLateModel(String serial, Future<String> lookup) {
    unawaited(lookup.then((model) {
      if (_known[serial]?.isReady != true) return;
      if (model.isEmpty || modelNames.containsKey(serial)) return;
      modelNames[serial] = model;
      _log('[+] $serial answered late: $model');
      onChanged?.call(_known);
    }, onError: (Object _) {}));
  }

  void _logAttached(AdbDevice device) {
    if (device.state == AdbDeviceState.unauthorized) {
      _log('[!] ${device.serial} connected but unauthorized: '
          'accept the prompt on the phone');
    } else if (!device.isReady) {
      _log('[?] ${device.serial} attached in state ${device.state.name}');
    }
  }
}
