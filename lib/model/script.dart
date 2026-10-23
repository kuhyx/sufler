import 'package:flutter/foundation.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/script_line.dart';

export 'package:sufler/model/script_line.dart';

/// A cast member as named in the script, with every spelling seen for them.
@immutable
class Character {
  /// Creates a character.
  const new({required this.id, required this.name, this.aliases = const []});

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => Character(
    id: json['id']! as String,
    name: json['name']! as String,
    aliases: stringList(json['aliases']),
  );

  /// Stable slug, unique within one [Script].
  final String id;

  /// Canonical display name ("Piaskowy Wilk").
  final String name;

  /// Other spellings folded into this character ("Piaksowy Wilk").
  final List<String> aliases;

  /// JSON form; see DOCS-contract.md.
  Json toJson() => {'id': id, 'name': name, 'aliases': aliases};
}

/// A contiguous run of lines: a scene or a song. Indices are inclusive.
@immutable
class Section {
  /// Creates a section.
  const new({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => Section(
    id: json['id']! as String,
    title: json['title']! as String,
    start: json['start']! as int,
    end: json['end']! as int,
  );

  /// Stable slug, unique within one [Script].
  final String id;

  /// Title exactly as written in the source ("Scena 3", "Piosenka Krasnali").
  final String title;

  /// Index of the first line in [Script.lines].
  final int start;

  /// Index of the last line in [Script.lines] (inclusive).
  final int end;

  /// JSON form; see DOCS-contract.md.
  Json toJson() => {'id': id, 'title': title, 'start': start, 'end': end};
}

/// A whole imported play: cast, scenes, songs and lines in reading order.
@immutable
class Script {
  /// Creates a script.
  const new({
    required this.id,
    required this.title,
    required this.source,
    required this.characters,
    required this.scenes,
    required this.songs,
    required this.lines,
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => Script(
    id: json['id']! as String,
    title: json['title']! as String,
    source: json['source']! as String,
    characters: objectList(json['characters'], Character.fromJson),
    scenes: objectList(json['scenes'], Section.fromJson),
    songs: objectList(json['songs'], Section.fromJson),
    lines: objectList(json['lines'], ScriptLine.fromJson),
  );

  /// Content hash of the source document; stable across re-imports.
  final String id;

  /// Play title.
  final String title;

  /// Original file name or URL the script was imported from.
  final String source;

  /// Cast, in order of first appearance (or cast list order).
  final List<Character> characters;

  /// Scenes in reading order. May have gaps/duplicates in numbering.
  final List<Section> scenes;

  /// Songs in reading order.
  final List<Section> songs;

  /// Every line; [ScriptLine.index] equals its position here.
  final List<ScriptLine> lines;

  /// JSON form; see DOCS-contract.md.
  Json toJson() => {
    'id': id,
    'title': title,
    'source': source,
    'characters': [for (final c in characters) c.toJson()],
    'scenes': [for (final s in scenes) s.toJson()],
    'songs': [for (final s in songs) s.toJson()],
    'lines': [for (final l in lines) l.toJson()],
  };
}
