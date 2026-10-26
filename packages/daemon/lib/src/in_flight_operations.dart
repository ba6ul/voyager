/// Which long-running wireless operation (Go Wireless or handoff) is running
/// for which USB serial.
///
/// Both operations send `adb tcpip`, which restarts adbd, and run for a long
/// time (Go Wireless waits up to 3 minutes for the user). Two of them for one
/// phone would restart adbd twice and race to launch a mirror, so a second
/// request is rejected, not queued. Everything runs on one isolate, so
/// [tryStart] is atomic as long as nothing awaits between a check and it.
class InFlightOperations {
  static const goWireless = 'Go Wireless';
  static const handoff = 'Handoff';

  final Map<String, String> _running = {};

  /// Reserves [serial] for [operation]. Returns null if it was reserved, or
  /// the name of the operation already running for that serial (in which case
  /// nothing changes).
  String? tryStart(String serial, String operation) {
    final current = _running[serial];
    if (current != null) return current;
    _running[serial] = operation;
    return null;
  }

  /// Releases [serial]. Safe to call more than once.
  void finish(String serial) => _running.remove(serial);

  /// The operation running for [serial], or null.
  String? runningFor(String serial) => _running[serial];

  /// A copy of the serials with an operation in flight.
  Set<String> get serials => _running.keys.toSet();
}
