import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/session.dart';
import 'package:sufler/rehearsal/similarity.dart';

/// Plays a partner line aloud (pack clip or device TTS). The future
/// completes when the line has finished playing.
abstract interface class LinePlayer {
  /// Plays [line]; completes when done.
  Future<void> play(ScriptLine line);

  /// Stops whatever is playing.
  Future<void> stop();
}

/// Drives a [RehearsalSession] in real time: plays partner lines through a
/// [LinePlayer] and runs the countdown for the actor's lines. With a
/// [capture] it also listens to each own line: the line ends when the
/// actor stops speaking, and the grade is suggested from what was heard.
class RehearsalController extends ChangeNotifier {
  /// Wraps [session]; call [start] to begin.
  new(
    this.session,
    this.player, {
    this.capture,
    this.tick = const Duration(milliseconds: 100),
  });

  /// Shortest pause [adjustPause] allows.
  static const double minPause = 0.5;

  /// Microphone for listening to own lines, if enabled.
  final SpeechCapture? capture;

  /// The underlying state machine.
  final RehearsalSession session;

  /// Partner line output.
  final LinePlayer player;

  /// Countdown resolution.
  final Duration tick;

  Timer? _timer;
  int _remainingMs = 0;
  int _generation = 0;
  bool _disposed = false;

  /// Whether the user paused the rehearsal.
  bool paused = false;

  /// Seconds left of the actor's current pause.
  double get remaining => _remainingMs / 1000;

  /// What the microphone heard of the current own line (null: nothing yet,
  /// or no recognizer).
  String? heard;

  /// Grade pre-selected from [heard]: ✓ when it matches the line.
  bool? suggestion;

  bool _listening = false;

  /// Begins at the session's current cue.
  void start() => _enter();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _halt() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    unawaited(player.stop());
    if (_listening) unawaited(capture?.cancel());
  }

  void _enter() {
    _timer?.cancel();
    final cue = session.current;
    if (cue != null && session.phase == Phase.partner) {
      unawaited(_playPartner(cue.line, ++_generation));
    } else if (session.phase == Phase.prompt) {
      unawaited(_playPartner(session.prompt!.line, ++_generation));
    } else if (cue != null && session.phase == Phase.mine) {
      _remainingMs = (cue.seconds * 1000).round();
      heard = null;
      suggestion = null;
      _runCountdown();
      if (capture != null) unawaited(_listen(cue.line, _generation));
    }
    _notify();
  }

  Future<void> _listen(ScriptLine line, int gen) async {
    _listening = true;
    final take = await capture!.listen();
    _listening = false;
    if (gen != _generation || _disposed || take == null) return;
    heard = take.transcript;
    suggestion = suggestedGrade(line.text, heard);
    if (session.phase == Phase.mine && !paused) {
      done();
    } else {
      _notify();
    }
  }

  /// Lengthens (or with a negative [delta], shortens) the current own
  /// line's pause, the running countdown with it; returns the new length.
  double adjustPause(double delta) {
    final cue = session.current!;
    final next = (cue.seconds + delta).clamp(minPause, 600.0);
    session.cues[session.position] = withSeconds(cue, next);
    if (session.phase == Phase.mine) {
      final ms = _remainingMs + ((next - cue.seconds) * 1000).round();
      _remainingMs = ms.clamp(tick.inMilliseconds, 600000);
    }
    _notify();
    return next;
  }

  Future<void> _playPartner(ScriptLine line, int gen) async {
    try {
      await player.play(line);
    } on Object catch (e) {
      debugPrint('partner line ${line.index} failed: $e');
    }
    if (gen != _generation || paused || _disposed) return;
    session.partnerDone();
    _enter();
  }

  void _runCountdown() {
    _timer = Timer.periodic(tick, (_) {
      _remainingMs -= tick.inMilliseconds;
      if (_remainingMs <= 0) {
        _remainingMs = 0;
        done();
      } else {
        _notify();
      }
    });
  }

  /// The actor finished their line ("done" tap / Space / countdown end).
  void done() {
    if (session.phase != Phase.mine) return;
    _timer?.cancel();
    // Keep listening's result for the grade; stop recording now.
    if (_listening) unawaited(capture!.finish());
    session.finishPause();
    _enter();
  }

  /// Self-grade of the line just said; ✗ replays the prompt and asks the
  /// line again. Returns whether it was the line's first attempt.
  bool grade({required bool ok}) {
    final first = session.grade(ok: ok);
    _enter();
    return first;
  }

  /// Jump to the next cue.
  void skip() => _jump(session.skip);

  /// Go back one cue.
  void back() => _jump(session.back);

  /// Start the whole section over.
  void restart() => _jump(session.restart);

  void _jump(void Function() move) {
    _halt();
    paused = false;
    move();
    _enter();
  }

  /// Freeze: stop audio and the countdown.
  void pause() {
    if (paused) return;
    paused = true;
    _halt();
    _notify();
  }

  /// Continue: replay the partner line (or prompt), or resume the countdown.
  void resume() {
    if (!paused) return;
    paused = false;
    if (session.phase case Phase.partner || Phase.prompt) {
      _enter();
    } else if (session.phase == Phase.mine) {
      _runCountdown();
      _notify();
    } else {
      _notify();
    }
  }

  @override
  void dispose() {
    _halt();
    _disposed = true;
    super.dispose();
  }
}
