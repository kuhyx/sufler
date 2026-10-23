import 'dart:async';
import 'dart:typed_data';

import 'package:sufler/rehearsal/partner_player.dart';

/// The raw audio output under [LatestClipPlayer] (audioplayers in the app).
abstract interface class ClipOutput {
  /// Starts playing [bytes]; completes once playback has begun.
  Future<void> start(Uint8List bytes, String mimeType);

  /// Stops playback.
  Future<void> halt();

  /// Fires when a clip played to its end.
  Stream<void> get completed;
}

/// Plays one clip at a time on [output]. Every [play] or [stop] supersedes
/// the requests before it (a generation counter), and output calls are
/// serialised: a newer request waits until an older `start` has returned,
/// then halts it, so a slow start from a skipped step can neither restart
/// nor land on the clip that replaced it.
class LatestClipPlayer implements ClipPlayer {
  /// Plays on [output].
  new(this.output);

  /// Where clips play.
  final ClipOutput output;

  int _generation = 0;
  Future<void> _calls = Future.value();
  Completer<void>? _playing;

  /// Runs [call] after every output call issued before it.
  Future<T> _serial<T>(Future<T> Function() call) {
    final result = _calls.then((_) => call());
    _calls = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Ends the current request: its [play] returns.
  int _supersede() {
    final p = _playing;
    if (p != null && !p.isCompleted) p.complete();
    _playing = null;
    return ++_generation;
  }

  @override
  Future<void> play(Uint8List bytes, String mimeType) async {
    final gen = _supersede();
    final done = _playing = Completer<void>();
    final sub = output.completed.listen((_) {
      if (gen == _generation && !done.isCompleted) done.complete();
    });
    try {
      final started = await _serial(() async {
        if (gen != _generation) return false;
        await output.halt();
        if (gen != _generation) return false;
        await output.start(bytes, mimeType);
        return true;
      });
      // A newer request came while this one was starting: it halts the
      // output itself once this start has returned.
      if (!started || gen != _generation) return;
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> stop() async {
    final gen = _supersede();
    await _serial(() async {
      if (gen == _generation) await output.halt();
    });
  }
}
