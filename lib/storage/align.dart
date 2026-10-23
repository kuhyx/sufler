import 'dart:typed_data';

import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/similarity.dart';

/// Similarity at which two unmatched lines in the same gap are the same
/// line reworded by the parser (a word moved to a heading, a split).
const double gapMatch = 0.6;

String _key(ScriptLine l) {
  final words = normalizedWords(l.text).join(' ');
  if (words.isNotEmpty) return words;
  // Lines without text (directions, tags): their kind and directions.
  return '\u0000${l.kind.name}:${l.directions.join('|')}';
}

/// Old line index -> new line index for every line of [old] that survives
/// in [fresh]: the longest common subsequence of normalised texts, then
/// in-order similar pairs inside each gap between matches.
Map<int, int> alignLines(List<ScriptLine> old, List<ScriptLine> fresh) {
  final ids = <String, int>{};
  final a = [for (final l in old) ids.putIfAbsent(_key(l), () => ids.length)];
  final b = [for (final l in fresh) ids.putIfAbsent(_key(l), () => ids.length)];
  final n = a.length;
  final m = b.length;
  final w = m + 1;
  // lcs[i * w + j] = LCS length of a[i..] and b[j..].
  final lcs = Int32List((n + 1) * w);
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i * w + j] = a[i] == b[j]
          ? lcs[(i + 1) * w + j + 1] + 1
          : (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]
                ? lcs[(i + 1) * w + j]
                : lcs[i * w + j + 1]);
    }
  }
  final pairs = <int, int>{};
  var i = 0;
  var j = 0;
  var gapI = 0;
  var gapJ = 0;
  void fillGap(int endI, int endJ) {
    var next = gapJ;
    for (var x = gapI; x < endI; x++) {
      for (var y = next; y < endJ; y++) {
        if (wordSimilarity(old[x].text, fresh[y].text) >= gapMatch &&
            normalizedWords(old[x].text).isNotEmpty) {
          pairs[x] = y;
          next = y + 1;
          break;
        }
      }
    }
  }

  while (i < n && j < m) {
    if (a[i] == b[j]) {
      fillGap(i, j);
      pairs[i] = j;
      i++;
      j++;
      (gapI, gapJ) = (i, j);
    } else if (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  fillGap(n, m);
  return pairs;
}
