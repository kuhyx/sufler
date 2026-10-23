import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';

/// What a line is, which decides how rehearsal treats it.
enum LineKind {
  /// Spoken dialogue (black text).
  dialogue,

  /// One sung lyric line (red text, or under a "Piosenka" heading).
  song,

  /// One recited verse line (blue text).
  recitation,

  /// A stage direction standing on its own; never spoken, never carded.
  direction,

  /// A structural heading (scene/song title); shown, never spoken.
  heading,
}

/// One unit of rehearsal: a speech block, or a single lyric/verse line.
@immutable
class ScriptLine {
  /// Creates a line.
  const new({
    required this.index,
    required this.speakers,
    required this.text,
    required this.kind,
    this.sceneId,
    this.songId,
    this.directions = const [],
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => ScriptLine(
    index: json['index']! as int,
    speakers: stringList(json['speakers']),
    text: json['text']! as String,
    kind: LineKind.values.byName(json['kind']! as String),
    sceneId: json['sceneId'] as String?,
    songId: json['songId'] as String?,
    directions: stringList(json['directions']),
  );

  /// Position in [Script.lines].
  final int index;

  /// Character ids speaking this line. Empty = unattributed (e.g. a chorus
  /// lyric whose singers the source does not name).
  final List<String> speakers;

  /// What is said, with stage directions removed. Line breaks preserved.
  final String text;

  /// How rehearsal treats the line.
  final LineKind kind;

  /// Containing scene, if any.
  final String? sceneId;

  /// Containing song, if any.
  final String? songId;

  /// Stage directions stripped from [text] ("(Wzdycha)", "/.../" excluded).
  final List<String> directions;

  /// Whether rehearsal reads this line aloud / expects it from the actor:
  /// not a direction or heading, and [text] has a letter or digit ("..."
  /// alone is a beat, not speech, and the voice service renders no clip).
  bool get isSpoken =>
      kind != LineKind.direction && kind != LineKind.heading && hasWords(text);

  /// JSON form; see DOCS-contract.md.
  Json toJson() => {
    'index': index,
    'speakers': speakers,
    'text': text,
    'kind': kind.name,
    if (sceneId != null) 'sceneId': sceneId,
    if (songId != null) 'songId': songId,
    if (directions.isNotEmpty) 'directions': directions,
  };

  /// Copy with some fields replaced (used by the correction screen).
  ScriptLine copyWith({List<String>? speakers, String? text, LineKind? kind}) =>
      ScriptLine(
        index: index,
        speakers: speakers ?? this.speakers,
        text: text ?? this.text,
        kind: kind ?? this.kind,
        sceneId: sceneId,
        songId: songId,
        directions: directions,
      );
}

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether [text] has at least one letter or digit, i.e. something to say.
bool hasWords(String text) => _wordChar.hasMatch(text);
