import 'dart:async';

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

  /// Walk over (all lines timed, stopped, or the mic failed).
  done,
}

/// Saves one take as the timing of [line].
typedef TakeSaver = Future<void> Function(ScriptLine line, CaptureResult take);

/// How many later lines a take is compared with to spot a skipped line.
const int skipLookahead = 3;

/// "Nagraj czasy": walks [lines] one by one, listens to each until the
/// actor stops speaking, saves the take and moves on without a tap.
class TimingSession extends ChangeNotifier {
  /// Creates the walk; call [run].
  new({required this.lines, required this.capture, required this.save});

  /// The actor's lines to time, in order.
  final List<ScriptLine> lines;

  /// The microphone.
  final SpeechCapture capture;

  /// Persists a take.
  final TakeSaver save;

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

  /// Why the walk ended early (mic unavailable), if it did.
  String? problem;

  bool _stopped = false;
  bool _disposed = false;
  Completer<bool>? _decision;

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
      state = TakeState.listening;
      _notify();
      final take = await capture.listen();
      if (_stopped) break;
      if (take == null) {
        problem = 'Nie słyszę mikrofonu';
        break;
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

  Future<void> _keep(int index, CaptureResult take) async {
    await save(lines[index], take);
    saved++;
    lastLine = lines[index];
    position = index + 1;
  }

  /// The take really was the later line: keep it there and go on after it.
  void accept() => _decision?.complete(true);

  /// Read the current line again.
  void redo() => _decision?.complete(false);

  /// Ends the walk; the line being listened to is not saved.
  Future<void> stop() async {
    _stopped = true;
    _decision?.complete(false);
    await capture.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_stopped) unawaited(stop());
    super.dispose();
  }
}
