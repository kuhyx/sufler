/// Runs: stretches said in one go (a song, a long monologue), by the actor
/// (recorded and learnt as one unit) or by his partners (played as one
/// step), instead of line by line.
library;

import 'package:flutter/foundation.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/cues.dart';

/// Own lines in a row that make a spoken run.
const int minSpokenRun = 3;

/// Own lyric lines in a row that make a sung run.
const int minSongRun = 2;

/// Consecutive own lines with no partner line in between, or partner
/// lines with no own line in between ([mine] false).
@immutable
class LineRun {
  /// Creates a run.
  const new({required this.lines, this.songId, this.mine = true});

  /// The actor's run, or his partners'.
  final bool mine;

  /// The lines, in order (at least two).
  final List<ScriptLine> lines;

  /// The song they belong to; null for a spoken run.
  final String? songId;

  /// Whether line [index] is part of the run.
  bool contains(int index) => lines.any((l) => l.index == index);
}

/// Every run of [roles] in [script]: a maximal row of own spoken lines
/// with no partner spoken line between them (directions and headings do
/// not break it). A song is its own unit (a row is cut where a song starts
/// or ends, and at a scene change); a sung row needs [minSongRun] lines,
/// a spoken one [minSpokenRun].
List<LineRun> findRuns(Script script, Set<Role> roles) {
  final runs = <LineRun>[];
  var row = <ScriptLine>[];
  void flush() {
    final song = row.isEmpty ? null : row.first.songId;
    if (row.length >= (song == null ? minSpokenRun : minSongRun)) {
      runs.add(LineRun(lines: row, songId: song));
    }
    row = [];
  }

  for (final line in script.lines) {
    if (!line.isSpoken) continue;
    if (!isMine(line, roles)) {
      flush();
      continue;
    }
    final prev = row.isEmpty ? null : row.last;
    if (prev != null &&
        (prev.songId != line.songId || prev.sceneId != line.sceneId)) {
      flush();
    }
    row.add(line);
  }
  flush();
  return runs;
}

/// Partner runs of [script] for [roles]: a row of partner spoken lines
/// with no own line between them, inside one song ([minSongRun] lines, any
/// singers) or by the very same speakers ([minSpokenRun] lines); cut at a
/// scene change like [findRuns].
List<LineRun> findPartnerRuns(Script script, Set<Role> roles) {
  final runs = <LineRun>[];
  var row = <ScriptLine>[];
  void flush() {
    final song = row.isEmpty ? null : row.first.songId;
    if (row.length >= (song == null ? minSpokenRun : minSongRun)) {
      runs.add(LineRun(lines: row, songId: song, mine: false));
    }
    row = [];
  }

  bool apart(ScriptLine a, ScriptLine b) =>
      a.songId != b.songId ||
      a.sceneId != b.sceneId ||
      (a.songId == null && !setEquals(a.speakers.toSet(), b.speakers.toSet()));

  for (final line in script.lines) {
    if (!line.isSpoken) continue;
    if (isMine(line, roles)) {
      flush();
      continue;
    }
    if (row.isNotEmpty && apart(row.last, line)) flush();
    row.add(line);
  }
  flush();
  return runs;
}

/// Own and partner runs together, for [mergeRuns].
List<LineRun> rehearsalRuns(Script script, Set<Role> roles) => [
  ...findRuns(script, roles),
  ...findPartnerRuns(script, roles),
];

/// The rehearsal walk over [plain] (unfolded cues): folded by [runs] when
/// given, then cut to the [missed] lines when given; [start] is the cue
/// holding script [line] (a resume point), else what was cue [position]
/// of the unfolded walk (points saved before lines were kept).
({List<Cue> cues, int start}) rehearsalWalk(
  List<Cue> plain, {
  List<LineRun>? runs,
  Set<int>? missed,
  int? line,
  int position = 0,
}) {
  final unfolded = missed == null ? plain : onlyMissed(plain, missed);
  final anchor =
      line ??
      (position < unfolded.length ? unfolded[position].line.index : null);
  var cues = runs == null ? plain : mergeRuns(plain, runs);
  if (missed != null) cues = onlyMissed(cues, missed);
  if (anchor == null || cues.isEmpty) return (cues: cues, start: 0);
  final at = cues.indexWhere((c) => c.lines.any((l) => l.index >= anchor));
  return (cues: cues, start: at < 0 ? cues.length - 1 : at);
}

/// [cues] with each row of cues inside one of [runs] folded into one cue
/// (two or more lines; a range may cut a run): an own one's pause is the
/// sum of theirs, so it is said, revealed and graded as one; a partner one
/// plays its lines back to back as one step.
List<Cue> mergeRuns(List<Cue> cues, List<LineRun> runs) {
  LineRun? runOf(Cue c) {
    for (final r in runs) {
      if (r.mine == c.mine && r.contains(c.line.index)) return r;
    }
    return null;
  }

  final out = <Cue>[];
  var i = 0;
  while (i < cues.length) {
    final run = runOf(cues[i]);
    var j = i + 1;
    while (run != null && j < cues.length && runOf(cues[j]) == run) {
      j++;
    }
    if (j - i < 2) {
      out.add(cues[i]);
    } else {
      final part = cues.sublist(i, j);
      out.add(
        Cue(
          line: part.first.line,
          mine: part.first.mine,
          seconds: part.fold(0, (sum, c) => sum + c.seconds),
          estimated: part.any((c) => c.estimated),
          following: [for (final c in part.skip(1)) c.line],
        ),
      );
    }
    i = j;
  }
  return out;
}
