import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/session.dart';

/// Plays a partner line aloud (pack clip or device TTS). The future
/// completes when the line has finished playing.
abstract interface class LinePlayer {
  /// Plays [line]; completes when done.
  Future<void> play(ScriptLine line);

  /// Stops whatever is playing.
  Future<void> stop();
}

/// Drives a [RehearsalSession] in real time: plays partner lines through a
/// [LinePlayer] and runs the countdown for the actor's lines.
class RehearsalController extends ChangeNotifier {
  /// Wraps [session]; call [start] to begin.
  new(
    this.session,
    this.player, {
    this.tick = const Duration(milliseconds: 100),
  });

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
  }

  void _enter() {
    _timer?.cancel();
    final cue = session.current;
    if (cue != null && session.phase == Phase.partner) {
      unawaited(_playPartner(cue.line, ++_generation));
    } else if (cue != null && session.phase == Phase.mine) {
      _remainingMs = (cue.seconds * 1000).round();
      _runCountdown();
    }
    _notify();
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
    session.finishPause();
    _enter();
  }

  /// Self-grade of the line just said.
  void grade({required bool ok}) {
    session.grade(ok: ok);
    _enter();
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

  /// Continue: replay the partner line, or resume the countdown.
  void resume() {
    if (!paused) return;
    paused = false;
    if (session.phase == Phase.partner) {
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
