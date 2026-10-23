import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';

/// How the actor's own line text is shown.
enum TextVisibility {
  /// Read-through: the text is on screen from the start.
  show,

  /// Never shown, not even when grading.
  hide,

  /// Learning (default): hidden while the actor says it, shown once they
  /// are done, then graded ✓/✗.
  revealAfter,
}

/// Schema version written by [AppSettings.toJson].
const int settingsVersion = 2;

/// App-wide rehearsal settings (not part of the per-script contract).
///
/// Version 1 (no `version` key) defaulted to showing the text up front, and
/// stored that default; loading it moves `show` to learning mode once.
@immutable
class AppSettings {
  /// Creates settings.
  const new({
    this.visibility = TextVisibility.revealAfter,
    this.selfGrade = false,
    this.loop = false,
    this.cleanTarget = 3,
    this.listen = false,
    this.wholeRuns = true,
    this.lastScriptId,
  });

  /// Parses [json] produced by [toJson] (any version).
  factory fromJson(Json json) {
    final old = (json['version'] as int? ?? 1) < settingsVersion;
    final stored = TextVisibility.values.byName(
      json['visibility'] as String? ?? 'revealAfter',
    );
    return AppSettings(
      visibility: old && stored == TextVisibility.show
          ? TextVisibility.revealAfter
          : stored,
      selfGrade: json['selfGrade'] as bool? ?? false,
      loop: json['loop'] as bool? ?? false,
      cleanTarget: json['cleanTarget'] as int? ?? 3,
      listen: json['listen'] as bool? ?? false,
      wholeRuns: json['wholeRuns'] as bool? ?? true,
      lastScriptId: json['lastScriptId'] as String?,
    );
  }

  /// Own-line text visibility.
  final TextVisibility visibility;

  /// Ask ✓/✗ after each own line in read-through mode too.
  final bool selfGrade;

  /// Repeat the section until [cleanTarget] clean passes.
  final bool loop;

  /// Consecutive clean passes needed in loop mode.
  final int cleanTarget;

  /// Listen through the microphone while the actor says a line: ends the
  /// line when they stop and suggests the grade from what was heard.
  final bool listen;

  /// Say a song or a run of own lines (`runs.dart`) in one go: one
  /// countdown, one reveal, one grade for the whole run.
  final bool wholeRuns;

  /// The script opened last; the app starts on it.
  final String? lastScriptId;

  /// Whether a ✓/✗ step follows each own line.
  bool get grades => selfGrade || loop || visibility != TextVisibility.show;

  /// JSON form.
  Json toJson() => {
    'version': settingsVersion,
    'visibility': visibility.name,
    'selfGrade': selfGrade,
    'loop': loop,
    'cleanTarget': cleanTarget,
    'listen': listen,
    'wholeRuns': wholeRuns,
    'lastScriptId': ?lastScriptId,
  };

  /// Copy with some fields replaced.
  AppSettings copyWith({
    TextVisibility? visibility,
    bool? selfGrade,
    bool? loop,
    int? cleanTarget,
    bool? listen,
    bool? wholeRuns,
    String? lastScriptId,
  }) => AppSettings(
    visibility: visibility ?? this.visibility,
    selfGrade: selfGrade ?? this.selfGrade,
    loop: loop ?? this.loop,
    cleanTarget: cleanTarget ?? this.cleanTarget,
    listen: listen ?? this.listen,
    wholeRuns: wholeRuns ?? this.wholeRuns,
    lastScriptId: lastScriptId ?? this.lastScriptId,
  );
}
