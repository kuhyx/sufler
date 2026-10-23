import 'package:meta/meta.dart';
import 'package:sufler/model/json.dart';

/// An explanation the assistant gave about part of a line ("Zapytaj
/// Claude"), kept with the line; JSON in DOCS-contract.md "Rehearsal prefs".
@immutable
class LineNote {
  /// Creates a note on [about] (the selected words) saying [text].
  const new({required this.about, required this.text});

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) =>
      LineNote(about: json['about']! as String, text: json['text']! as String);

  /// The selected word or span the note explains.
  final String about;

  /// The explanation.
  final String text;

  /// JSON form.
  Json toJson() => {'about': about, 'text': text};
}
