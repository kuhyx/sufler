/// Cutting one whole-run take (a song, a monologue) into its lines.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/rehearsal/pace.dart';
import 'package:sufler/rehearsal/similarity.dart';

/// Seconds into a take.
typedef Span = ({double start, double end});

/// [from]..[to] cut back to back, each of [texts] getting a share as large
/// as its spoken syllables (at least one): the fallback with no word times.
List<Span> splitBySyllables(List<String> texts, double from, double to) {
  final weights = [for (final t in texts) math.max(1, spokenSyllables(t))];
  final total = weights.fold(0, (a, b) => a + b);
  final out = <Span>[];
  var at = from;
  var done = 0;
  for (final w in weights) {
    done += w;
    final end = from + (to - from) * done / total;
    out.add((start: at, end: end));
    at = end;
  }
  return out;
}

/// Each of [lines] located in [words]: the heard words are aligned to the
/// expected ones (word edit distance, so misheard, missing and extra words
/// are fine) and a line runs from its first heard word to its last. A line
/// no word landed on shares the gap between its neighbours (or [from] /
/// [to]) by syllables.
List<Span> alignToLines(
  List<String> lines,
  List<TimedWord> words, {
  required double from,
  required double to,
}) {
  final ref = [
    for (final (i, l) in lines.indexed)
      for (final w in normalizedWords(l)) (word: w, line: i),
  ];
  final heard = [
    for (final w in words)
      for (final t in normalizedWords(w.text)) (word: t, at: w),
  ];
  final owner = _align(
    [for (final r in ref) r.word],
    [for (final h in heard) h.word],
  );
  final found = List<Span?>.filled(lines.length, null);
  int? last;
  for (final (j, h) in heard.indexed) {
    final r = owner[j];
    // An extra word belongs with the line before it (the first: after).
    final line = r != null ? ref[r].line : last ?? _firstOwned(owner, ref);
    if (line == null) continue;
    last = line;
    final had = found[line];
    found[line] = had == null
        ? (start: h.at.start, end: h.at.end)
        : (start: had.start, end: math.max(had.end, h.at.end));
  }
  return _fillGaps(lines, found, from, to);
}

int? _firstOwned(List<int?> owner, List<({String word, int line})> ref) {
  for (final r in owner) {
    if (r != null) return ref[r].line;
  }
  return null;
}

/// For each of [hyp], the index into [ref] it was aligned to (match or
/// substitution), null for an inserted word.
List<int?> _align(List<String> ref, List<String> hyp) {
  final n = ref.length;
  final m = hyp.length;
  final d = List.generate(n + 1, (i) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final sub = d[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1);
      d[i][j] = math.min(sub, math.min(d[i - 1][j], d[i][j - 1]) + 1);
    }
  }
  final out = List<int?>.filled(m, null);
  var i = n;
  var j = m;
  while (i > 0 && j > 0) {
    final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
    if (d[i][j] == d[i - 1][j - 1] + cost) {
      out[--j] = --i;
    } else if (d[i][j] == d[i][j - 1] + 1) {
      j--;
    } else {
      i--;
    }
  }
  return out;
}

/// Spans of [found] made back to back (no overlap), the missing ones
/// filled by [splitBySyllables] over the gap they leave.
List<Span> _fillGaps(
  List<String> lines,
  List<Span?> found,
  double from,
  double to,
) {
  final out = <Span>[];
  var i = 0;
  while (i < lines.length) {
    final prevEnd = out.isEmpty ? from : out.last.end;
    final f = found[i];
    if (f != null) {
      out.add((
        start: math.max(f.start, prevEnd),
        end: math.max(f.end, prevEnd),
      ));
      i++;
      continue;
    }
    var j = i;
    while (j < lines.length && found[j] == null) {
      j++;
    }
    final next = j < lines.length ? found[j]!.start : to;
    out.addAll(
      splitBySyllables(lines.sublist(i, j), prevEnd, math.max(prevEnd, next)),
    );
    i = j;
  }
  return out;
}

/// Where the voice is in a whole take (WAV from `pcmToWav`): from the
/// first to the last 20 ms frame clearly above the room's noise; null when
/// nothing is.
Span? speechSpan(Uint8List wav, {double minRms = 0.01, double ratio = 3}) {
  if (wav.length <= 44) return null;
  final b = ByteData.sublistView(wav);
  final rate = b.getUint32(24, Endian.little);
  final block = b.getUint16(32, Endian.little);
  final frame = math.max(1, rate ~/ 50);
  final frames = (wav.length - 44) ~/ block ~/ frame;
  double rms(int f) {
    var sum = 0.0;
    for (var s = 0; s < frame; s++) {
      final v = b.getInt16(44 + (f * frame + s) * block, Endian.little) / 32768;
      sum += v * v;
    }
    return math.sqrt(sum / frame);
  }

  final levels = [for (var f = 0; f < frames; f++) rms(f)];
  if (levels.isEmpty) return null;
  // A long take has quiet moments (before, breaths, after): its quietest
  // tenth is the room.
  final floor = ([...levels]..sort())[levels.length ~/ 10];
  final threshold = math.max(minRms, floor * ratio);
  final first = levels.indexWhere((l) => l > threshold);
  if (first < 0) return null;
  final last = levels.lastIndexWhere((l) => l > threshold);
  return (start: first * frame / rate, end: (last + 1) * frame / rate);
}
