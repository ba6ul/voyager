import 'dart:io';

/// Runs [body] as a fire-and-forget task that can never end the daemon.
///
/// An error that escapes an un-awaited future (or an async timer/stream
/// callback) is uncaught and terminates the Dart process, taking every scrcpy
/// mirror the daemon owns with it. This logs the failure with [label],
/// optionally reports it through [onError] (e.g. to emit a `failed` status
/// event so a UI is not left waiting), and always completes normally.
///
/// This is the safety net, not the first line of defence: operations should
/// still handle the failures they expect and report them precisely.
Future<void> guarded(
  String label,
  Future<void> Function() body, {
  void Function(Object error, StackTrace stack)? onError,
  void Function(String message)? log,
}) async {
  final write = log ?? stdout.writeln;
  try {
    await body();
  } catch (error, stack) {
    write('[!] $label failed: $error');
    if (onError != null) {
      try {
        onError(error, stack);
      } catch (reportError) {
        write('[!] $label: could not report the failure: $reportError');
      }
    }
  }
}
