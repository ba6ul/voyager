/// Shared IPC layer between the scrcpy_gui daemon and any client (UI, tools).
///
/// Wire format: newline-delimited JSON over a loopback TCP socket.
/// One JSON object per line, UTF-8 encoded.
///
/// Client -> daemon:
///   {"type": "cmd", "id": "<client-chosen id>", "cmd": "<name>", "args": {...}}
///
/// Daemon -> client (reply to a specific command):
///   {"type": "result", "id": "<same id>", "ok": true,  "data": {...}}
///   {"type": "result", "id": "<same id>", "ok": false, "error": "<message>"}
///
/// Daemon -> all clients (unsolicited, no id):
///   {"type": "event", "event": "<name>", "data": {...}}
library scrcpy_ipc;

export 'src/messages.dart';
export 'src/ipc_server.dart';
export 'src/ipc_client.dart';
