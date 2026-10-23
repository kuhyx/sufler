import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/similarity.dart';

/// What the timing walk is doing.
enum TakeState {
  /// Listening to the actor read the current line.
  listening,

  /// What was heard matches a later line: accept it or redo.
  skipped,

  /// No usable take: the actor says the line and taps "Skończyłem".
  manual,

  /// Walk over (all lines timed, stopped, or the mic failed).
  done,
}

/// Saves one take as the timing of [line].
typedef TakeSaver = Future<void> Function(ScriptLine line, CaptureResult take);

/// Saves a tapped timing: [seconds] is the whole pause for [line].
typedef TimeSaver = Future<void> Function(ScriptLine line, double seconds);

/// How many later lines a take is compared with to spot a skipped line.
const int skipLookahead = 3;

/// "Nagraj czasy": walks [lines] one by one, listens to each until the
/// actor stops speaking, saves the take and moves on without a tap. When
/// the mic hears nothing (or in [manualAll]) the line is timed by a tap
/// instead: from when it was shown to "Skończyłem", saved as its pause.
class TimingSession extends ChangeNotifier {
  /// Creates the walk; call [run].
  new({
    required this.lines,
    required this.capture,
    required this.save,
    required this.saveTime,
    this.clock = DateTime.now,
    bool manual = false,
  }) : _manualAll = manual;

  /// The actor's lines to time, in order.
  final List<ScriptLine> lines;

  /// The microphone.
  final SpeechCapture capture;

  /// Persists a take.
  final TakeSaver save;

  /// Persists a tapped timing (no recording).
  final TimeSaver saveTime;

  /// Wall clock; a line's time runs from when it is shown.
  final DateTime Function() clock;

  /// Whether every line is timed by tapping, without the mic.
  bool get manualAll => _manualAll;
  bool _manualAll;

  /// Pause saved by the latest tap, shown instead of [lastTake].
  double? lastPause;

  /// Index into [lines] being read.
  int position = 0;

  /// Current state.
  TakeState state = TakeState.listening;

  /// The latest take (shown as "saved 3,2 s" or under a skip prompt).
  CaptureResult? lastTake;

  /// Line the latest take was saved for.
  ScriptLine? lastLine;

  /// Index into [lines] the take seems to belong to, in [TakeState.skipped].
  int? skipTo;

  /// Lines saved so far.
  int saved = 0;

  /// Why the current line is timed by a tap (mic heard nothing), if so.
  String? problem;

  bool _stopped = false;
  bool _disposed = false;
  Completer<bool>? _decision;
  Completer<void>? _tap;

  /// The line being read; null when done.
  ScriptLine? get current => state == TakeState.done || position >= lines.length
      ? null
      : lines[position];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Runs the walk to the end (or [stop]).
  Future<void> run() async {
    while (!_stopped && position < lines.length) {
      final shown = clock();
      problem = null;
      final take = _manualAll ? null : await _listen();
      if (_stopped) break;
      if (take == null || _empty(take)) {
        // A cancel from [setManual] is not a mic failure.
        if (!_manualAll) problem = 'Nie słyszę mikrofonu';
        if (!await _tapped()) break;
        await _keepTime(position, clock().difference(shown));
        continue;
      }
      final later = [
        for (final l in lines.skip(position + 1).take(skipLookahead)) l.text,
      ];
      final other = matchesOther(lines[position].text, take.transcript, later);
      lastTake = take;
      if (other == null) {
        await _keep(position, take);
        continue;
      }
      skipTo = position + 1 + other;
      state = TakeState.skipped;
      _notify();
      final accepted = await (_decision = Completer<bool>()).future;
      _decision = null;
      if (_stopped) break;
      if (accepted) await _keep(skipTo!, take);
      skipTo = null;
    }
    state = TakeState.done;
    _notify();
  }

  Future<CaptureResult?> _listen() {
    state = TakeState.listening;
    _notify();
    return capture.listen();
  }

  /// Nothing heard at all: no speech span and no words.
  static bool _empty(CaptureResult take) =>
      take.durationSeconds <= 0 && (take.transcript ?? '').trim().isEmpty;

  /// Waits for "Skończyłem"; false when the walk was stopped instead.
  Future<bool> _tapped() async {
    state = TakeState.manual;
    _notify();
    await (_tap = Completer<void>()).future;
    _tap = null;
    return !_stopped;
  }

  Future<void> _keep(int index, CaptureResult take) async {
    await save(lines[index], take);
    _saved(index, null);
  }

  /// Saves [took] (rounded to 0.1 s, at least 0.1 s) as the pause.
  Future<void> _keepTime(int index, Duration took) async {
    final pause = math.max(0.1, (took.inMilliseconds / 100).round() / 10);
    await saveTime(lines[index], pause);
    lastTake = null;
    _saved(index, pause);
  }

  void _saved(int index, double? pause) {
    saved++;
    lastPause = pause;
    lastLine = lines[index];
    position = index + 1;
  }

  /// The take really was the later line: keep it there and go on after it.
  void accept() => _decision?.complete(true);

  /// Read the current line again.
  void redo() => _decision?.complete(false);

  /// "Skończyłem": the actor finished the line in [TakeState.manual].
  void finished() => _complete(_tap);

  /// Times the rest of the walk by tapping ([on]) or by the mic again
  /// (from the next line). Switching on mid-listen drops that take.
  void setManual({required bool on}) {
    if (_manualAll == on) return;
    _manualAll = on;
    _notify();
    if (on && state == TakeState.listening) unawaited(capture.cancel());
  }

  static void _complete(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Ends the walk; the line being listened to is not saved.
  Future<void> stop() async {
    _stopped = true;
    _decision?.complete(false);
    _complete(_tap);
    await capture.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_stopped) unawaited(stop());
    super.dispose();
  }
}
