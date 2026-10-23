import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/role.dart';

/// Per-script rehearsal prefs; JSON shape in DOCS-contract.md
/// "Rehearsal prefs".
@immutable
class RehearsalPrefs {
  /// Creates prefs.
  const RehearsalPrefs({
    this.roles = const {},
    this.speed = 1,
    this.lineSeconds = const {},
    this.recordings = const {},
  });

  /// Parses [json] produced by [toJson].
  factory RehearsalPrefs.fromJson(Json json) => RehearsalPrefs(
    roles: {for (final r in stringList(json['roles'])) Role.parse(r)},
    speed: (json['speed'] as num? ?? 1).toDouble(),
    lineSeconds: {
      for (final e in (json['lineSeconds'] as Json? ?? const {}).entries)
        int.parse(e.key): (e.value! as num).toDouble(),
    },
    recordings: {
      for (final e in (json['recordings'] as Json? ?? const {}).entries)
        int.parse(e.key): e.value! as String,
    },
  );

  /// Picked characters and songs.
  final Set<Role> roles;

  /// Global speed multiplier (0.5-3).
  final double speed;

  /// Manual per-line pause overrides, seconds.
  final Map<int, double> lineSeconds;

  /// Line index -> storage key of the actor's own recording.
  final Map<int, String> recordings;

  /// JSON form.
  Json toJson() => {
    'roles': [for (final r in roles) r.toString()],
    'speed': speed,
    'lineSeconds': {for (final e in lineSeconds.entries) '${e.key}': e.value},
    'recordings': {for (final e in recordings.entries) '${e.key}': e.value},
  };

  /// Copy with some fields replaced.
  RehearsalPrefs copyWith({
    Set<Role>? roles,
    double? speed,
    Map<int, double>? lineSeconds,
    Map<int, String>? recordings,
  }) => RehearsalPrefs(
    roles: roles ?? this.roles,
    speed: speed ?? this.speed,
    lineSeconds: lineSeconds ?? this.lineSeconds,
    recordings: recordings ?? this.recordings,
  );
}

/// How the actor's own line text is shown during their pause.
enum TextVisibility {
  /// Always visible.
  show,

  /// Never shown.
  hide,

  /// Hidden during the pause, shown once it ends.
  revealAfter,
}

/// App-wide rehearsal settings (not part of the per-script contract).
@immutable
class AppSettings {
  /// Creates settings.
  const AppSettings({
    this.visibility = TextVisibility.show,
    this.selfGrade = false,
    this.loop = false,
    this.cleanTarget = 3,
  });

  /// Parses [json] produced by [toJson].
  factory AppSettings.fromJson(Json json) => AppSettings(
    visibility: TextVisibility.values.byName(
      json['visibility'] as String? ?? 'show',
    ),
    selfGrade: json['selfGrade'] as bool? ?? false,
    loop: json['loop'] as bool? ?? false,
    cleanTarget: json['cleanTarget'] as int? ?? 3,
  );

  /// Own-line text visibility.
  final TextVisibility visibility;

  /// Ask ✓/✗ after each own line.
  final bool selfGrade;

  /// Repeat the section until [cleanTarget] clean passes.
  final bool loop;

  /// Consecutive clean passes needed in loop mode.
  final int cleanTarget;

  /// JSON form.
  Json toJson() => {
    'visibility': visibility.name,
    'selfGrade': selfGrade,
    'loop': loop,
    'cleanTarget': cleanTarget,
  };

  /// Copy with some fields replaced.
  AppSettings copyWith({
    TextVisibility? visibility,
    bool? selfGrade,
    bool? loop,
    int? cleanTarget,
  }) => AppSettings(
    visibility: visibility ?? this.visibility,
    selfGrade: selfGrade ?? this.selfGrade,
    loop: loop ?? this.loop,
    cleanTarget: cleanTarget ?? this.cleanTarget,
  );
}
