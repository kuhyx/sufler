import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/role.dart';

export 'package:sufler/model/line_note.dart';

export 'package:sufler/storage/app_settings.dart';

/// Grades kept per line (oldest dropped first).
const int knowledgeDepth = 20;

/// Where the actor stopped rehearsing: what, and how far in.
@immutable
class ResumePoint {
  /// Creates a resume point.
  const new({
    required this.label,
    required this.start,
    required this.end,
    this.position = 0,
    this.missedOnly = false,
    this.line,
    this.retry = false,
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => ResumePoint(
    label: json['label']! as String,
    start: json['start']! as int,
    end: json['end']! as int,
    position: json['position'] as int? ?? 0,
    missedOnly: json['mode'] == 'missed',
    line: json['line'] as int?,
    retry: json['retry'] as bool? ?? false,
  );

  /// Shown title ("Scena 3", "Kwestie 4–9").
  final String label;

  /// First line index of the range.
  final int start;

  /// Last line index of the range (inclusive).
  final int end;

  /// Cue position reached in the walk.
  final int position;

  /// "Only lines I missed" practice over the range.
  final bool missedOnly;

  /// Script line of the cue reached: what resumes, since the cue
  /// [position] shifts when runs are folded (or unfolded) into one cue.
  /// Null in points saved before it was kept.
  final int? line;

  /// The cue reached was graded ✗ on its first try and is being asked
  /// again: on resume that ✗ stands, so the next ✓ is not a first attempt
  /// (not stored as knowledge, the pass not clean).
  final bool retry;

  /// JSON form.
  Json toJson() => {
    'label': label,
    'start': start,
    'end': end,
    'position': position,
    'mode': missedOnly ? 'missed' : 'range',
    'line': ?line,
    // Only when set, so points without a retry keep their old shape.
    if (retry) 'retry': true,
  };

  /// Copy at another [position] (of script [line]); [retry]: its cue is
  /// being asked again after a ✗.
  ResumePoint at(int position, {int? line, bool retry = false}) => ResumePoint(
    label: label,
    start: start,
    end: end,
    position: position,
    missedOnly: missedOnly,
    line: line,
    retry: retry,
  );
}

/// Per-script rehearsal prefs; JSON shape in DOCS-contract.md
/// "Rehearsal prefs". Every field is optional when parsing, so prefs saved
/// by older versions load unchanged.
@immutable
class RehearsalPrefs {
  /// Creates prefs.
  const new({
    this.roles = const {},
    this.speed = 1,
    this.lineSeconds = const {},
    this.tapSeconds = const {},
    this.recordings = const {},
    this.knowledge = const {},
    this.resume,
    this.rolesAsked = false,
    this.pureRuns = const {},
    this.notes = const {},
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) {
    Map<int, T> byLine<T>(String key, T Function(Object?) read) => {
      for (final e in (json[key] as Json? ?? const {}).entries)
        int.parse(e.key): read(e.value),
    };
    final resume = json['resume'] as Json?;
    return RehearsalPrefs(
      roles: {for (final r in stringList(json['roles'])) Role.parse(r)},
      speed: (json['speed'] as num? ?? 1).toDouble(),
      lineSeconds: byLine('lineSeconds', (v) => (v! as num).toDouble()),
      tapSeconds: byLine('tapSeconds', (v) => (v! as num).toDouble()),
      recordings: byLine('recordings', (v) => v! as String),
      knowledge: byLine(
        'knowledge',
        (v) => [for (final b in v! as List) b as bool],
      ),
      resume: resume == null ? null : ResumePoint.fromJson(resume),
      // Prefs saved before the roles screen existed: ask only if none set.
      rolesAsked: json['rolesAsked'] as bool? ?? false,
      pureRuns: stringList(json['pureRuns']).toSet(),
      notes: byLine('notes', (v) => objectList(v, LineNote.fromJson)),
    );
  }

  /// Picked characters, songs and groups.
  final Set<Role> roles;

  /// Global speed multiplier (0.5-3).
  final double speed;

  /// Manual per-line pause overrides, seconds.
  final Map<int, double> lineSeconds;

  /// Line index -> seconds timed by a tap in "Nagraj czasy" (line shown to
  /// "Skończyłem"): a pace sample like a recording. The pause itself is
  /// the [lineSeconds] entry the tap also wrote.
  final Map<int, double> tapSeconds;

  /// Line index -> storage key of the actor's own recording.
  final Map<int, String> recordings;

  /// Line index -> first-attempt self-grades (one per pass), oldest first
  /// (true = knew it). Retries after a ✗ are not recorded.
  final Map<int, List<bool>> knowledge;

  /// Where the last rehearsal stopped.
  final ResumePoint? resume;

  /// Whether the roles screen was already shown once for this script.
  final bool rolesAsked;

  /// Ids of scenes/songs once rehearsed whole with every own line ✓ on
  /// the first try ("czysty przebieg").
  final Set<String> pureRuns;

  /// Line index -> the assistant's notes on it, oldest first.
  final Map<int, List<LineNote>> notes;

  /// Copy with [note] added to line [index].
  RehearsalPrefs withNote(int index, LineNote note) => copyWith(
    notes: {
      ...notes,
      index: [...?notes[index], note],
    },
  );

  /// Copy with section [id] marked as purely run.
  RehearsalPrefs withPureRun(String id) =>
      copyWith(pureRuns: {...pureRuns, id});

  /// Lines whose latest first-attempt grade is ✗.
  Set<int> get missed => {
    for (final e in knowledge.entries)
      if (e.value.isNotEmpty && !e.value.last) e.key,
  };

  /// Copy with [ok] appended to line [index]'s grades.
  RehearsalPrefs graded(int index, {required bool ok}) {
    final old = knowledge[index] ?? const <bool>[];
    final next = [...old, ok];
    return copyWith(
      knowledge: {
        ...knowledge,
        index: next.length > knowledgeDepth
            ? next.sublist(next.length - knowledgeDepth)
            : next,
      },
    );
  }

  /// JSON form.
  Json toJson() => {
    'roles': [for (final r in roles) r.toString()],
    'speed': speed,
    'lineSeconds': {for (final e in lineSeconds.entries) '${e.key}': e.value},
    if (tapSeconds.isNotEmpty)
      'tapSeconds': {for (final e in tapSeconds.entries) '${e.key}': e.value},
    'recordings': {for (final e in recordings.entries) '${e.key}': e.value},
    'knowledge': {for (final e in knowledge.entries) '${e.key}': e.value},
    'resume': ?resume?.toJson(),
    'rolesAsked': rolesAsked,
    // Only when set, so prefs without pure runs keep their old shape.
    if (pureRuns.isNotEmpty) 'pureRuns': [...pureRuns],
    if (notes.isNotEmpty)
      'notes': {
        for (final e in notes.entries)
          '${e.key}': [for (final n in e.value) n.toJson()],
      },
  };

  /// Copy with some fields replaced; [clearResume] drops [resume].
  RehearsalPrefs copyWith({
    Set<Role>? roles,
    double? speed,
    Map<int, double>? lineSeconds,
    Map<int, double>? tapSeconds,
    Map<int, String>? recordings,
    Map<int, List<bool>>? knowledge,
    ResumePoint? resume,
    bool clearResume = false,
    bool? rolesAsked,
    Set<String>? pureRuns,
    Map<int, List<LineNote>>? notes,
  }) => RehearsalPrefs(
    roles: roles ?? this.roles,
    speed: speed ?? this.speed,
    lineSeconds: lineSeconds ?? this.lineSeconds,
    tapSeconds: tapSeconds ?? this.tapSeconds,
    recordings: recordings ?? this.recordings,
    knowledge: knowledge ?? this.knowledge,
    resume: clearResume ? null : resume ?? this.resume,
    rolesAsked: rolesAsked ?? this.rolesAsked,
    pureRuns: pureRuns ?? this.pureRuns,
    notes: notes ?? this.notes,
  );
}
