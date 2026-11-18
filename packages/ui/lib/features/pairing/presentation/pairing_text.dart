import '../../devices/domain/device_repository.dart';

/// Steps on the phone, shown above the form.
const pairingSteps = 'On the phone: Settings, Developer options, Wireless '
    'debugging, then "Pair device with pairing code". Type the address and '
    'the 6-digit code it shows. Both phone and PC must be on the same Wi-Fi.';

final _address = RegExp(r'^(\d{1,3})(\.\d{1,3}){3}:(\d{1,5})$');

/// Why [value] is not the pairing address, or null if it is. Mirrors the
/// daemon's check, so a typo is caught before anything is sent.
String? addressError(String value) {
  final text = value.trim();
  if (!_address.hasMatch(text)) {
    return 'Type the address as shown on the phone, like 192.168.1.8:37123.';
  }
  final colon = text.lastIndexOf(':');
  final port = int.parse(text.substring(colon + 1));
  final octets = text.substring(0, colon).split('.').map(int.parse);
  if (port < 1 || port > 65535 || octets.any((o) => o > 255)) {
    return 'That address is not valid. Check it on the phone.';
  }
  return null;
}

/// Why [value] is not a pairing code, or null if it is.
String? codeError(String value) =>
    RegExp(r'^\d{6}$').hasMatch(value.trim())
        ? null
        : 'The pairing code is 6 digits.';

/// Whether [stage] ends a pairing (the daemon sends nothing more).
bool isFinalPairingStage(String stage) => const {
      'connected',
      'pairedOnly',
      'wrongCode',
      'unreachable',
      'failed',
    }.contains(stage);

/// Whether the pairing worked (the phone is paired, connected or not).
bool pairingSucceeded(String stage) =>
    stage == 'connected' || stage == 'pairedOnly';

/// A plain sentence for one pairing status.
String describePairing(PairingStatus status) {
  final detail = status.detail;
  switch (status.stage) {
    case 'pairing':
      return 'Pairing with the phone…';
    case 'searching':
      return 'Paired. Looking for the phone to connect…';
    case 'connected':
      return detail == null
          ? 'Paired and connected.'
          : 'Paired and connected: $detail';
    case 'pairedOnly':
      return 'Paired, but the phone could not be found to connect. Make sure '
          'Wireless debugging is still on, then try again.';
    case 'wrongCode':
      return 'The phone did not accept that code. Check the 6 digits on the '
          'pairing dialog; it closes after a minute or two, so reopen it if '
          'needed.';
    case 'unreachable':
      return 'Nothing answered at that address. Keep the pairing dialog open '
          'on the phone, use the address it shows, and make sure the PC is '
          'on the same Wi-Fi.';
    case 'failed':
      return detail == null ? 'Pairing failed.' : 'Pairing failed: $detail';
    default:
      return 'Pairing: ${status.stage}${detail == null ? '' : ' ($detail)'}…';
  }
}
