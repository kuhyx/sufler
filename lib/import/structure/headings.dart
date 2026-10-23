/// Line-shape tests for the structural parts of a script.
library;

final _upper = RegExp(r'^[\p{Lu}\d]', unicode: true);
final _sentenceEnd = RegExp(r'[.!?…:;,\-–]$');
final _trailingParen = RegExp(r'\s*\(([^()]*)\)\s*$');
final _quotes = RegExp(r'^["„“”«»]+|["„“”«»]+$');

final _castHeader = RegExp(
  r'^(Bohaterowie|Osoby|Postacie|Obsada|Występują)\b[^.]*:?$',
  caseSensitive: false,
);

/// Normalises whitespace.
String squash(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// `Scena 3` (numbering as written); "Scena pogrążona w cieniu" is not one.
bool isSceneHeading(String line) {
  final t = squash(line);
  return RegExp(r'^Scena\s+\d+\b').hasMatch(t) &&
      t.split(' ').length <= 6 &&
      !RegExp(r'[.!?,]$').hasMatch(t);
}

/// The title of a `Piosenka ...` heading (quotes around it removed), or
/// null. Mid-sentence mentions of a song are not headings.
String? songTitle(String line) {
  var t = squash(line);
  if (t.startsWith(RegExp('["„“«]'))) t = t.replaceAll(_quotes, '');
  if (!RegExp(r'^Piosenka(\s|$)').hasMatch(t)) return null;
  if (t.split(' ').length > 8 || RegExp(r'[.!?,;:…]$').hasMatch(t)) {
    return null;
  }
  return t;
}

/// Splits `Name (direction)` into the name part and the direction.
(String, String?) splitTrailingDirection(String line) {
  final t = squash(line);
  final m = _trailingParen.firstMatch(t);
  if (m == null || m.start == 0) return (t, null);
  return (t.substring(0, m.start), '(${m[1]!.trim()})');
}

/// Speaker names in a heading-shaped line ("Błystek, Koszałek, Pietrzyk",
/// "Lis i Róża"), or null when the line cannot be a heading: every name
/// is 1-3 capitalised words and the line does not end like a sentence.
List<String>? headingParts(String line, {int maxWords = 8}) {
  final t = squash(line);
  if (t.isEmpty || t.length > 60 || _sentenceEnd.hasMatch(t)) return null;
  if (t.contains(RegExp('[()"„”/]'))) return null;
  final parts = t.split(RegExp(r'\s*,\s*|\s+i\s+'));
  var words = 0;
  for (final p in parts) {
    final w = p.split(' ');
    words += w.length;
    if (p.isEmpty || w.length > 3 || !w.every(_upper.hasMatch)) return null;
  }
  return words <= maxWords ? parts : null;
}

/// The cast list after `Bohaterowie:` (or Osoby/Postacie/Obsada): bullet
/// entries with the source-tale parenthetical dropped, "X i Y" split.
/// Returns the names and the index of the last line consumed (-1: none).
(List<String>, int) castList(List<String> lines) {
  final header = _castHeader;
  final start = lines.indexWhere((l) => header.hasMatch(squash(l)));
  if (start < 0) return (const [], -1);
  final names = <String>[];
  var end = start;
  final bullet = RegExp(r'^[•·▪◦●*\-–]\s*(.+)$');
  for (var i = start + 1; i < lines.length; i++) {
    final t = squash(lines[i]);
    final m = bullet.firstMatch(t);
    if (m != null) {
      final entry = m[1]!.replaceAll(_trailingParen, '');
      names.addAll(entry.split(RegExp(r'\s*,\s*|\s+i\s+')).map(squash));
      end = i;
    } else if (t.isNotEmpty &&
        !RegExp(r'^\d+[.)]').hasMatch(t) &&
        !t.endsWith(':')) {
      break;
    }
  }
  return (names.where((n) => n.isNotEmpty).toList(), end);
}

/// The play title: the first quoted line near the top, else the first line.
String? findTitle(List<String> lines) {
  final top = lines
      .take(15)
      .map(squash)
      .takeWhile((l) => !_castHeader.hasMatch(l) && !isSceneHeading(l))
      .where((l) => l.isNotEmpty);
  for (final l in top) {
    if (RegExp(r'^["„“«].+["”»]$').hasMatch(l)) {
      return l.replaceAll(_quotes, '');
    }
  }
  return top.firstOrNull;
}
