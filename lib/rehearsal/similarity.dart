/// How close a transcript is to the line the actor should have said.
library;

import 'dart:math' as math;

/// Similarity at or above which "knew it" (✓) is suggested.
const double knewItSimilarity = 0.8;

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lowercase words of [text], punctuation and spacing dropped.
List<String> normalizedWords(String text) => [
  for (final w in text.toLowerCase().split(_nonWord))
    if (w.isNotEmpty) w,
];

/// Word-level similarity of [a] and [b] in 0..1: one minus the word edit
/// distance over the longer word count. Two empty texts are identical.
double wordSimilarity(String a, String b) {
  final x = normalizedWords(a);
  final y = normalizedWords(b);
  final longest = math.max(x.length, y.length);
  if (longest == 0) return 1;
  var prev = List<int>.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i++) {
    final row = List<int>.filled(y.length + 1, 0)..[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      row[j] = math.min(
        math.min(row[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    prev = row;
  }
  return 1 - prev[y.length] / longest;
}

/// The grade to pre-select for [heard] against [expected]: ✓ when similar
/// enough, ✗ otherwise, null with no transcript.
bool? suggestedGrade(String expected, String? heard) =>
    heard == null ? null : wordSimilarity(expected, heard) >= knewItSimilarity;

/// Index into [others] of a line [heard] clearly matches instead of
/// [expected] (the actor skipped ahead), or null.
int? matchesOther(String expected, String? heard, List<String> others) {
  if (heard == null) return null;
  final own = wordSimilarity(expected, heard);
  if (own >= knewItSimilarity) return null;
  int? best;
  var bestScore = knewItSimilarity;
  for (final (i, text) in others.indexed) {
    final score = wordSimilarity(text, heard);
    if (score >= bestScore && score > own) {
      (best, bestScore) = (i, score);
    }
  }
  return best;
}
