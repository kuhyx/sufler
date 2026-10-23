import 'package:sufler/model/json.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/storage/prefs.dart';

/// Per-line prefs moved to a new parse: which lines' data moved, which
/// was lost (its line is gone), and old -> new recording line indices.
typedef PrefsMove = ({
  RehearsalPrefs prefs,
  Set<int> moved,
  Set<int> lost,
  Map<int, int> recordings,
});

/// Moves [p]'s per-line data through [map] (old -> new line index; see
/// `alignLines`). The resume range snaps to the nearest surviving lines.
PrefsMove movePrefs(RehearsalPrefs p, Map<int, int> map, int newLength) {
  final moved = <int>{};
  final lost = <int>{};
  Map<int, T> move<T>(Map<int, T> data) {
    final out = <int, T>{};
    for (final e in data.entries) {
      final to = map[e.key];
      if (to == null) {
        lost.add(e.key);
        continue;
      }
      if (to != e.key) moved.add(e.key);
      out[to] = e.value;
    }
    return out;
  }

  final recordings = {
    for (final k in p.recordings.keys)
      if (map[k] != null) k: map[k]!,
  };
  final r = p.resume;
  ResumePoint? resume;
  if (r != null && newLength > 0) {
    final last = map.keys.fold(r.end, (a, b) => a > b ? a : b);
    int near(int at, int step) {
      for (var i = at; i >= 0 && i <= last; i += step) {
        final to = map[i];
        if (to != null) return to;
      }
      return step > 0 ? newLength - 1 : 0;
    }

    final start = near(r.start, 1);
    final end = near(r.end, -1);
    resume = ResumePoint(
      label: r.label,
      start: start < end ? start : end,
      end: start < end ? end : start,
      position: r.position,
      missedOnly: r.missedOnly,
    );
  }
  return (
    prefs: RehearsalPrefs(
      roles: p.roles,
      speed: p.speed,
      lineSeconds: move(p.lineSeconds),
      tapSeconds: move(p.tapSeconds),
      recordings: move(p.recordings),
      knowledge: move(p.knowledge),
      resume: resume,
      rolesAsked: p.rolesAsked,
      pureRuns: p.pureRuns,
      notes: move(p.notes),
    ),
    moved: moved,
    lost: lost,
    recordings: recordings,
  );
}

/// One logged manual correction (CorrectionScreen), replayed on re-parse.
typedef Correction = Json;

/// A correction of line [index]'s speakers, kind and/or text; [was] is
/// the text before a text edit (re-parse aligns by it).
Correction lineCorrection(
  int index, {
  List<String>? speakers,
  LineKind? kind,
  String? text,
  String? was,
}) => {
  'op': 'line',
  'index': index,
  'speakers': ?speakers,
  'kind': ?kind?.name,
  'text': ?text,
  'was': ?was,
};

/// [s] with the text edits in [log] undone (newest first): the text each
/// line had as parsed, which is what a new parse is aligned against.
Script revertTexts(Script s, List<Correction> log) {
  var out = s;
  for (final c in log.reversed) {
    final i = c['index'] as int?;
    final was = c['was'] as String?;
    if (c['op'] != 'line' || i == null || was == null) continue;
    if (i < out.lines.length) out = editLine(out, i, text: was);
  }
  return out;
}

/// A merge of character [from] into [into].
Correction mergeCorrection({required String from, required String into}) => {
  'op': 'merge',
  'from': from,
  'into': into,
};

/// Merges a script stored before corrections were logged must have had:
/// an old character whose alias is the name of a separate character in
/// [fresh] (the parser split it again).
List<Correction> inferMerges(Script old, Script fresh) => [
  for (final c in old.characters)
    for (final f in fresh.characters)
      if (f.id != c.id &&
          !old.characters.any((o) => o.id == f.id) &&
          c.aliases.any((a) => a.toLowerCase() == f.name.toLowerCase()))
        mergeCorrection(from: f.id, into: c.id),
];

/// [fresh] with [log] replayed, line indices moved through [map]. Returns
/// the corrected script, the log with new indices, and how many entries
/// were applied / dropped (line gone or character missing).
({Script script, List<Correction> log, int applied, int dropped})
replayCorrections(Script fresh, List<Correction> log, Map<int, int> map) {
  var s = fresh;
  final out = <Correction>[];
  var dropped = 0;
  for (final c in log) {
    if (c['op'] == 'merge') {
      final from = c['from']! as String;
      final into = c['into']! as String;
      final ids = {for (final ch in s.characters) ch.id};
      if (!ids.contains(from) || !ids.contains(into)) {
        dropped++;
        continue;
      }
      s = mergeCharacter(s, from: from, into: into);
      out.add(c);
      continue;
    }
    final to = map[c['index']! as int];
    if (to == null) {
      dropped++;
      continue;
    }
    final kind = c['kind'] as String?;
    s = editLine(
      s,
      to,
      speakers: c['speakers'] == null ? null : stringList(c['speakers']),
      kind: kind == null ? null : LineKind.values.byName(kind),
      text: c['text'] as String?,
    );
    out.add({...c, 'index': to});
  }
  return (script: s, log: out, applied: out.length, dropped: dropped);
}
