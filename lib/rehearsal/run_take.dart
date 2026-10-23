import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/run_split.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/rehearsal/wav.dart';

/// The microphone for a whole-run take: a plain recorder ended by a tap
/// (silence must not end a song), plus the desktop recognizer, if any.
@immutable
class RunMic {
  /// Creates the mic from a recorder's [start]/[stop] and [transcribe].
  const new({required this.start, required this.stop, this.transcribe});

  /// Starts recording; false when the mic is not available.
  final Future<bool> Function() start;

  /// Stops; the whole take as WAV (null: nothing recorded).
  final Future<Uint8List?> Function() stop;

  /// Word times for the take (desktop voice service); null: none.
  final Transcribe? transcribe;
}

/// What the timing walk needs to offer whole-run takes.
@immutable
class WholeRuns {
  /// Creates the bundle.
  const new({required this.runs, required this.mic, this.hasRecording});

  /// The script's runs for the actor's roles (`findRuns`).
  final List<LineRun> runs;

  /// Recorder and recognizer.
  final RunMic mic;

  /// Whether a line already has a recording (asked before replacing it).
  final Future<bool> Function(ScriptLine line)? hasRecording;
}

/// One slice of [wav] per line of [lines]: cut by the heard words when
/// [heard] has word times, else by syllables over the voiced part.
List<CaptureResult> sliceTake(
  List<ScriptLine> lines,
  Uint8List wav,
  Transcript? heard,
) {
  final texts = [for (final l in lines) l.text];
  final whole = wavSeconds(wav);
  final List<Span> spans;
  if (heard != null && heard.words.isNotEmpty) {
    spans = alignToLines(
      texts,
      heard.words,
      from: heard.speechStart ?? 0,
      to: heard.speechEnd ?? whole,
    );
  } else {
    final voiced = speechSpan(wav) ?? (start: 0.0, end: whole);
    spans = splitBySyllables(texts, voiced.start, voiced.end);
  }
  return [
    for (final s in spans)
      CaptureResult(
        speechStart: s.start,
        speechEnd: s.end,
        audio: trimWav(wav, s.start, s.end),
      ),
  ];
}

/// "3 kwestie", "5 kwestii", "1 kwestia".
String linesLabel(int n) {
  final ten = n % 10;
  final few = ten >= 2 && ten <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${n == 1
      ? 'kwestia'
      : few
      ? 'kwestie'
      : 'kwestii'}';
}

/// "Nagraj w całości": [lines] recorded nonstop in one take, then split.
class RunTake {
  /// Creates the take; [hasRecording] tells which lines already have one.
  new({required this.lines, required this.mic, this.hasRecording});

  /// The run's lines in the walk.
  final List<ScriptLine> lines;

  /// Recorder and recognizer.
  final RunMic mic;

  /// Whether a line already has a recording (asked before replacing it).
  final Future<bool> Function(ScriptLine line)? hasRecording;

  /// Lines of the run that already have a recording, once asked.
  int existing = 0;

  /// What came of the take ("Zapisano…", or why nothing).
  String? note;

  bool _cancelled = false;
  final Completer<void> _end = Completer<void>();
  Completer<bool>? _choice;

  /// Records until [finish], then the slice to save per line; existing
  /// recordings stay unless the user says so ([ask] is called, then
  /// [overwrite] answers). Null when nothing was recorded or [cancel]led.
  Future<Map<ScriptLine, CaptureResult>?> record({
    required void Function() ask,
  }) async {
    if (!await mic.start()) {
      note = 'Nie nagrano w całości: brak mikrofonu';
      return null;
    }
    await _end.future;
    final wav = await mic.stop();
    if (_cancelled) return null;
    if (wav == null || wavSeconds(wav) <= 0) {
      note = 'Nie nagrano w całości: nic nie słychać';
      return null;
    }
    final heard = await mic.transcribe?.call(wav);
    final slices = sliceTake(lines, wav, heard);
    final had = <ScriptLine>{
      for (final l in lines)
        if (await hasRecording?.call(l) ?? false) l,
    };
    if (_cancelled) return null;
    var keep = const <ScriptLine>{};
    if (had.isNotEmpty) {
      existing = had.length;
      ask();
      final replace = await (_choice = Completer<bool>()).future;
      if (_cancelled) return null;
      if (!replace) keep = had;
    }
    return {
      for (final (i, l) in lines.indexed)
        if (!keep.contains(l)) l: slices[i],
    };
  }

  /// The actor finished the run.
  void finish() {
    if (!_end.isCompleted) _end.complete();
  }

  /// Replace the existing recordings ([yes]) or keep them.
  void overwrite({required bool yes}) {
    final c = _choice;
    if (c != null && !c.isCompleted) c.complete(yes);
  }

  /// Abandons the take (stopping the recorder); nothing is saved.
  void cancel() {
    _cancelled = true;
    finish();
    overwrite(yes: false);
  }
}
