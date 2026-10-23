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

/// Whether [line] is an end-of-play marker ("Koniec", "KONIEC.",
/// "Koniec;)", "Kurtyna"): a closing note, never anyone's line.
bool isEndMarker(String line) => RegExp(
  r'^(koniec|kurtyna)[\s.!;:,)(*~-]*$',
  caseSensitive: false,
).hasMatch(squash(line));

/// `Scena 3` (numbering as written); "Scena pogrążona w cieniu" is not one.
bool isSceneHeading(String line) {
  final t = squash(line);
  return RegExp(r'^Scena\s+\d+\b').hasMatch(t) &&
      t.split(' ').length <= 6 &&
      !RegExp(r'[.!?,]$').hasMatch(t);
}

/// A section marker on its own line: `Scena 3`, or a structural word
/// ("Finał", "EPILOG.", "Prolog:", "Wstęp", "Antrakt", "Akt 2", "Akt II";
/// trailing `.`/`:` dropped from the title). `scene`: it opens a scene
/// section (Scena, Finał, Epilog, Prolog); the others are headings inside
/// the current one.
({String title, bool scene})? sectionHeading(String line) {
  final t = squash(line);
  if (isSceneHeading(t)) return (title: t, scene: true);
  final title = t.replaceFirst(RegExp(r'\s*[.:]$'), '');
  final m = RegExp(
    r'^(?:(finał|epilog|prolog)|wstęp|antrakt|akt\s+(?:\d+|[ivxlc]+))$',
    caseSensitive: false,
    unicode: true,
  ).firstMatch(title);
  return m == null ? null : (title: title, scene: m[1] != null);
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

/// A cast-list group ("1. Krasnale:") and the names listed under it.
typedef CastGroup = ({String name, List<String> members});

/// The cast list after `Bohaterowie:` (or Osoby/Postacie/Obsada): bullet
/// entries with the source-tale parenthetical dropped, "X i Y" split, and
/// the numbered groups they sit in ("1. Krasnale:", quotes dropped).
/// Returns the names, the index of the last line consumed (-1: none) and
/// the groups.
(List<String>, int, List<CastGroup>) castList(List<String> lines) {
  final header = _castHeader;
  final start = lines.indexWhere((l) => header.hasMatch(squash(l)));
  if (start < 0) return (const [], -1, const []);
  final names = <String>[];
  final groups = <CastGroup>[];
  var end = start;
  final bullet = RegExp(r'^[•·▪◦●*\-–]\s*(.+)$');
  final group = RegExp(r'^\d+[.)]\s*(.*?)\s*:?$');
  for (var i = start + 1; i < lines.length; i++) {
    final t = squash(lines[i]);
    final m = bullet.firstMatch(t);
    final g = group.firstMatch(t);
    if (m != null) {
      final entry = m[1]!.replaceAll(_trailingParen, '');
      final found = entry.split(RegExp(r'\s*,\s*|\s+i\s+')).map(squash);
      final kept = found.where((n) => n.isNotEmpty);
      names.addAll(kept);
      groups.lastOrNull?.members.addAll(kept);
      end = i;
    } else if (g != null) {
      final name = squash(g[1]!.replaceAll(RegExp('["„“”«»]'), ''));
      if (name.isNotEmpty) groups.add((name: name, members: []));
    } else if (t.isNotEmpty && !t.endsWith(':')) {
      break;
    }
  }
  return (names, end, [...groups.where((g) => g.members.isNotEmpty)]);
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
