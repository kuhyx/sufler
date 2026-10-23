import 'package:flutter/foundation.dart';

/// What a text colour means in a script.
enum Tint {
  /// Black / dark grey: dialogue, headings, directions.
  normal,

  /// Red: sung lyrics.
  song,

  /// Blue: recited verse.
  recitation,
}

/// Maps a 0xRRGGBB fill colour to its [Tint]. Null (unknown) is normal.
///
/// The known script colours (#c9211e, #ff0000, #bf0041 red; #2a6099 blue)
/// hit the hue tests below, which also accept nearby shades.
Tint tintOf(int? rgb) {
  if (rgb == null) return Tint.normal;
  final r = (rgb >> 16) & 0xff;
  final g = (rgb >> 8) & 0xff;
  final b = rgb & 0xff;
  if (r >= 0x99 && g <= 0x60 && b <= 0x70) return Tint.song;
  if (b >= 0x80 && b >= r + 0x40 && b >= g + 0x20) return Tint.recitation;
  return Tint.normal;
}

/// A piece of text with one fill colour.
@immutable
class TextRun {
  /// Creates a run; [rgb] is 0xRRGGBB or null when unknown.
  const TextRun(this.text, [this.rgb]);

  /// The characters.
  final String text;

  /// Fill colour as 0xRRGGBB, null when the source has none.
  final int? rgb;
}

/// One visual line of the source document with its dominant colour.
@immutable
class StyledLine {
  /// Creates a line.
  const StyledLine(this.text, {this.tint = Tint.normal, this.wraps = false});

  /// Builds a line from runs; the tint is the one covering most letters.
  factory StyledLine.fromRuns(List<TextRun> runs, {bool wraps = false}) {
    final counts = <Tint, int>{};
    for (final run in runs) {
      final letters = run.text.replaceAll(RegExp(r'\s'), '').length;
      final tint = tintOf(run.rgb);
      counts[tint] = (counts[tint] ?? 0) + letters;
    }
    var best = Tint.normal;
    var bestCount = 0;
    counts.forEach((tint, count) {
      if (count > bestCount) (best, bestCount) = (tint, count);
    });
    return StyledLine(runs.map((r) => r.text).join(), tint: best, wraps: wraps);
  }

  /// The line's text (may contain leading/trailing spaces).
  final String text;

  /// Dominant colour meaning.
  final Tint tint;

  /// True when the paragraph continues on the next line (a soft wrap in a
  /// PDF), so the structurer joins the two with a space.
  final bool wraps;

  @override
  String toString() => '$tint:$text';
}
