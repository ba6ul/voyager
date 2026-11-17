import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/domain/device_repository.dart';
import 'package:scrcpy_ui/features/devices/presentation/progress_text.dart';

String describe(ProgressKind kind, String stage, [String? detail]) =>
    describeProgress(
        kind, StatusEvent(serial: 'R58M12ABCDE', stage: stage, detail: detail));

void main() {
  // Every stage documented in packages/ipc messages.dart, with a detail where
  // the daemon sends one.
  const wirelessStages = <(String, String?)>[
    ('alreadyRunning', 'Go Wireless is already in progress for this phone'),
    ('waitingForPhone', 'the phone did not answer the last request'),
    ('readingWifiIp', null),
    ('tcpipEnabled', null),
    ('waitingForHotspot', null),
    ('connecting', '192.168.43.1:5555'),
    ('connected', '192.168.43.1:5555'),
    ('failed', 'timed out after 3 minutes'),
  ];
  const handoffStages = <(String, String?)>[
    ('alreadyRunning', 'Go Wireless is in progress for this phone'),
    ('waitingForPhone', 'the phone did not answer the last request'),
    ('readingWifiIp', null),
    ('tcpipEnabled', null),
    ('tcpipUnconfirmed', 'the phone did not acknowledge the switch'),
    ('connecting', null),
    ('launchingWireless', null),
    ('closingUsb', null),
    ('complete', '192.168.43.1:5555'),
    ('failed', 'could not reach the device over WiFi'),
  ];

  // camelCase stage names (waitingForHotspot, tcpipEnabled...) are internal
  // identifiers; single-word ones (failed, connecting) are ordinary words.
  group('no documented stage shows its camelCase name', () {
    final camelCase = RegExp('[A-Z]');
    for (final (kind, stages) in [
      (ProgressKind.wireless, wirelessStages),
      (ProgressKind.handoff, handoffStages),
    ]) {
      for (final (stage, detail) in stages) {
        test('${kind.name} $stage', () {
          final text = describe(kind, stage, detail);
          if (camelCase.hasMatch(stage)) {
            expect(text, isNot(contains(stage)));
          }
          expect(text, isNot(startsWith('${kind == ProgressKind.wireless ? 'Go Wireless' : 'Handoff'}: $stage')),
              reason: 'not the unknown-stage fallback');
        });
      }
    }
  });

  group('Go Wireless', () {
    test('tells the user what to do while it waits for the PC to reach the '
        'phone', () {
      final text = describe(ProgressKind.wireless, 'waitingForHotspot');
      expect(text, contains("Turn on the phone's hotspot"));
      expect(text, contains('same Wi-Fi'));
    });

    test('keeps the instruction while it tries addresses', () {
      final text =
          describe(ProgressKind.wireless, 'connecting', '192.168.43.1:5555');
      expect(text, contains(hotspotInstruction));
      expect(text, contains('Trying 192.168.43.1:5555'));
    });

    test('says where it connected and that the cable can go', () {
      expect(
        describe(ProgressKind.wireless, 'connected', '192.168.43.1:5555'),
        'Connected wirelessly at 192.168.43.1:5555. '
        'You can unplug the USB cable.',
      );
    });

    test('keeps the reason of a failure and of a turned-away request', () {
      expect(describe(ProgressKind.wireless, 'failed', 'timed out after 3 minutes'),
          'Go Wireless failed: timed out after 3 minutes');
      expect(
        describe(ProgressKind.wireless, 'alreadyRunning',
            'Go Wireless is already in progress for this phone'),
        'Go Wireless not started: Go Wireless is already in progress for this '
        'phone',
      );
    });
  });

  group('Handoff', () {
    test('says the PC must already reach the phone, since it does not wait',
        () {
      final text = describe(ProgressKind.handoff, 'connecting');
      expect(text, contains("already be on the phone's hotspot or the same "
          'Wi-Fi'));
    });

    test('says where it is mirroring and that the cable can go', () {
      expect(
        describe(ProgressKind.handoff, 'complete', '10.0.0.5:5555'),
        'Now mirroring wirelessly at 10.0.0.5:5555. '
        'You can unplug the USB cable.',
      );
    });

    test('keeps the reason of a failure', () {
      expect(
          describe(ProgressKind.handoff, 'failed',
              'could not reach the device over WiFi'),
          'Handoff failed: could not reach the device over WiFi');
    });
  });

  test('a failure without a reason is still a sentence', () {
    expect(describe(ProgressKind.handoff, 'failed'), 'Handoff failed.');
  });

  test('a stage this UI does not know still reads', () {
    expect(describe(ProgressKind.wireless, 'someNewStage', 'detail'),
        'Go Wireless: someNewStage (detail)');
    expect(describe(ProgressKind.handoff, 'someNewStage'),
        'Handoff: someNewStage');
  });

  test('final stages are the ones after which the daemon sends nothing more',
      () {
    for (final stage in ['connected', 'complete', 'failed', 'alreadyRunning']) {
      expect(isFinalStage(stage), isTrue, reason: stage);
    }
    for (final stage in [
      'waitingForPhone',
      'readingWifiIp',
      'tcpipEnabled',
      'tcpipUnconfirmed',
      'waitingForHotspot',
      'connecting',
      'launchingWireless',
      'closingUsb',
    ]) {
      expect(isFinalStage(stage), isFalse, reason: stage);
    }
  });
}
