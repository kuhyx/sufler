import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/role.dart';

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
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => ResumePoint(
    label: json['label']! as String,
    start: json['start']! as int,
    end: json['end']! as int,
    position: json['position'] as int? ?? 0,
    missedOnly: json['mode'] == 'missed',
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

  /// JSON form.
  Json toJson() => {
    'label': label,
    'start': start,
    'end': end,
    'position': position,
    'mode': missedOnly ? 'missed' : 'range',
  };

  /// Copy at another [position].
  ResumePoint at(int position) => ResumePoint(
    label: label,
    start: start,
    end: end,
    position: position,
    missedOnly: missedOnly,
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
    this.recordings = const {},
    this.knowledge = const {},
    this.resume,
    this.rolesAsked = false,
    this.pureRuns = const {},
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
      recordings: byLine('recordings', (v) => v! as String),
      knowledge: byLine(
        'knowledge',
        (v) => [for (final b in v! as List) b as bool],
      ),
      resume: resume == null ? null : ResumePoint.fromJson(resume),
      // Prefs saved before the roles screen existed: ask only if none set.
      rolesAsked: json['rolesAsked'] as bool? ?? false,
      pureRuns: stringList(json['pureRuns']).toSet(),
    );
  }

  /// Picked characters, songs and groups.
  final Set<Role> roles;

  /// Global speed multiplier (0.5-3).
  final double speed;

  /// Manual per-line pause overrides, seconds.
  final Map<int, double> lineSeconds;

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
    'recordings': {for (final e in recordings.entries) '${e.key}': e.value},
    'knowledge': {for (final e in knowledge.entries) '${e.key}': e.value},
    'resume': ?resume?.toJson(),
    'rolesAsked': rolesAsked,
    // Only when set, so prefs without pure runs keep their old shape.
    if (pureRuns.isNotEmpty) 'pureRuns': [...pureRuns],
  };

  /// Copy with some fields replaced; [clearResume] drops [resume].
  RehearsalPrefs copyWith({
    Set<Role>? roles,
    double? speed,
    Map<int, double>? lineSeconds,
    Map<int, String>? recordings,
    Map<int, List<bool>>? knowledge,
    ResumePoint? resume,
    bool clearResume = false,
    bool? rolesAsked,
    Set<String>? pureRuns,
  }) => RehearsalPrefs(
    roles: roles ?? this.roles,
    speed: speed ?? this.speed,
    lineSeconds: lineSeconds ?? this.lineSeconds,
    recordings: recordings ?? this.recordings,
    knowledge: knowledge ?? this.knowledge,
    resume: clearResume ? null : resume ?? this.resume,
    rolesAsked: rolesAsked ?? this.rolesAsked,
    pureRuns: pureRuns ?? this.pureRuns,
  );
}
