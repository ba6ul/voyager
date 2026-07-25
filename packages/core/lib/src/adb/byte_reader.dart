import 'dart:async';
import 'dart:typed_data';

/// A linear memory buffer designed to synchronize variable-length socket data streams.
///
/// This utility wraps a native raw socket stream subscription, accumulating inbound byte arrays 
/// into a contiguous memory heap. It abstracts fragmentation over network layers, exposing linear 
/// asynchronous hooks to extract absolute byte slices safely without data race conditions.
///
/// Stream Synchronization Mechanics:
/// 1. Accumulation: Automatically monitors and appends inbound TCP segment slices to an internal cache.
/// 2. Evaluation: Interrogates structural length constraints sequentially via state completers, throwing on premature termination (EOF).
/// 3. Extraction: Erases processed ranges automatically to prevent memory leaks during continuous socket parsing.
class ByteReader {
  ByteReader(Stream<List<int>> stream) {
    _sub = stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _tryComplete();
      },
      onError: (Object e, StackTrace s) {
        _error = e;
        _tryComplete();
      },
      onDone: () {
        _done = true;
        _tryComplete();
      },
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buffer = <int>[];
  bool _done = false;
  Object? _error;

  int? _wanted;
  Completer<Uint8List>? _pending;

  /// Reads exactly [n] bytes. Throws [StateError] on EOF before [n] bytes.
  Future<Uint8List> readBytes(int n) {
    if (_pending != null) {
      throw StateError('concurrent readBytes calls are not supported');
    }
    final completer = Completer<Uint8List>();
    _wanted = n;
    _pending = completer;
    _tryComplete();
    return completer.future;
  }

  /// Reads until the stream closes and returns everything.
  Future<Uint8List> readToEnd() {
    if (_pending != null) {
      throw StateError('concurrent reads are not supported');
    }
    final completer = Completer<Uint8List>();
    _wanted = -1;
    _pending = completer;
    _tryComplete();
    return completer.future;
  }

  void _tryComplete() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;

    if (_error != null) {
      final e = _error!;
      _pending = null;
      pending.completeError(e);
      return;
    }

    final wanted = _wanted!;
    if (wanted == -1) {
      if (_done) {
        final out = Uint8List.fromList(_buffer);
        _buffer.clear();
        _pending = null;
        pending.complete(out);
      }
      return;
    }

    if (_buffer.length >= wanted) {
      final out = Uint8List.fromList(_buffer.sublist(0, wanted));
      _buffer.removeRange(0, wanted);
      _pending = null;
      pending.complete(out);
    } else if (_done) {
      _pending = null;
      pending.completeError(
        StateError(
          'socket closed: wanted $wanted bytes, got ${_buffer.length}',
        ),
      );
    }
  }

  Future<void> cancel() => _sub.cancel();
}
