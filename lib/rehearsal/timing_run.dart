part of 'timing_session.dart';

/// "Nagraj w całości" inside the timing walk: at the first line of a run
/// the whole run can be recorded nonstop, then cut into its lines.
extension WholeRun on TimingSession {
  /// Walk lines from here one take can cover: a run that starts (in the
  /// walk) at the current line, with at least two of its lines; else 0.
  int get runHere {
    final w = whole;
    final at = current;
    if (w == null || manualAll || state != TakeState.listening || at == null) {
      return 0;
    }
    for (final r in w.runs) {
      if (!r.contains(at.index)) continue;
      if (position > 0 && r.contains(lines[position - 1].index)) return 0;
      var n = 1;
      while (position + n < lines.length &&
          r.contains(lines[position + n].index)) {
        n++;
      }
      return n >= 2 ? n : 0;
    }
    return 0;
  }

  /// Outcome of the latest whole-run take.
  String? get runNote => runTake?.note;

  /// The run being recorded whole.
  List<ScriptLine>? get runLines => runTake?.lines;

  /// How many of its lines already have a recording ([TakeState.overwrite]).
  int get runExisting => runTake?.existing ?? 0;

  /// Drops the line take under way and records the run nonstop instead.
  void recordRun() {
    if (runHere == 0) return;
    _wantRun = true;
    unawaited(capture.cancel());
  }

  /// Replace ([yes]) or keep the run's existing recordings.
  void overwrite({required bool yes}) => runTake?.overwrite(yes: yes);

  Future<void> _whole() async {
    _wantRun = false;
    final n = runHere;
    if (n == 0) return;
    final take = runTake = RunTake(
      lines: lines.sublist(position, position + n),
      mic: whole!.mic,
      hasRecording: whole!.hasRecording,
    );
    state = TakeState.run;
    _notify();
    final slices = await take.record(
      ask: () {
        state = TakeState.overwrite;
        _notify();
      },
    );
    state = TakeState.listening;
    if (_stopped || slices == null) return;
    for (final MapEntry(key: line, value: slice) in slices.entries) {
      await save(line, slice);
    }
    saved += slices.length;
    lastTake = lastPause = lastLine = null;
    take.note = 'Zapisano w całości: ${linesLabel(slices.length)}';
    position += take.lines.length;
  }
}
