import '../domain/device_repository.dart';

/// Which flow a progress event belongs to.
enum ProgressKind { wireless, handoff }

/// What the user has to do while Go Wireless looks for the phone. The daemon
/// prints the same advice in its console (packages/daemon wireless.dart).
const hotspotInstruction = "Turn on the phone's hotspot and connect this PC "
    'to it, or keep both on the same Wi-Fi.';

/// Stages after which the daemon sends nothing more for that request (see
/// `IpcEvents.wirelessStatus` / `IpcEvents.handoffStatus` in packages/ipc).
const _finalStages = {'connected', 'complete', 'failed', 'alreadyRunning'};

/// Whether [stage] ends its flow.
bool isFinalStage(String stage) => _finalStages.contains(stage);

/// A plain sentence for one Go Wireless or Handoff progress event, in place
/// of the daemon's stage name. Keeps the daemon's detail where it carries
/// information (an address, a reason). A stage this UI does not know (a newer
/// daemon) still reads as the flow's name, the stage and its detail.
String describeProgress(ProgressKind kind, StatusEvent event) {
  final detail = event.detail;
  final flow = kind == ProgressKind.wireless ? 'Go Wireless' : 'Handoff';
  String withDetail(String text) => detail == null ? '$text.' : '$text: $detail';

  switch ((kind, event.stage)) {
    case (_, 'waitingForPhone'):
      return '$flow: waiting for the phone to be ready again after the last '
          'attempt…';
    case (_, 'readingWifiIp'):
      return '$flow: getting the phone ready…';
    case (_, 'tcpipEnabled'):
      return '$flow: the phone is ready for a wireless connection.';
    case (_, 'failed'):
      return withDetail('$flow failed');
    case (_, 'alreadyRunning'):
      return withDetail('$flow not started');

    // Go Wireless waits (up to a few minutes) for the PC to reach the phone,
    // so the instruction stays visible while it keeps trying addresses.
    case (ProgressKind.wireless, 'waitingForHotspot'):
      return 'Go Wireless: $hotspotInstruction Voyager connects by itself.';
    case (ProgressKind.wireless, 'connecting'):
      return 'Go Wireless: $hotspotInstruction '
          '${detail == null ? 'Looking for the phone…' : 'Trying $detail…'}';
    case (ProgressKind.wireless, 'connected'):
      return 'Connected wirelessly${detail == null ? '' : ' at $detail'}. '
          'You can unplug the USB cable.';

    // Handoff does not wait for a hotspot: it only tries to connect for a
    // short while, so the PC has to be able to reach the phone already.
    case (ProgressKind.handoff, 'tcpipUnconfirmed'):
      return 'Handoff: the phone did not confirm the switch; trying to '
          'connect anyway…';
    case (ProgressKind.handoff, 'connecting'):
      return "Handoff: looking for the phone over Wi-Fi. This PC must already "
          "be on the phone's hotspot or the same Wi-Fi.";
    case (ProgressKind.handoff, 'launchingWireless'):
      return 'Handoff: opening the wireless mirror…';
    case (ProgressKind.handoff, 'closingUsb'):
      return 'Handoff: closing the USB mirror…';
    case (ProgressKind.handoff, 'complete'):
      return 'Now mirroring wirelessly${detail == null ? '' : ' at $detail'}. '
          'You can unplug the USB cable.';
  }
  return '$flow: ${event.stage}${detail == null ? '' : ' ($detail)'}';
}
