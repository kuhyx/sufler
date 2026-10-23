import 'package:sufler/import/structure/cast.dart';
import 'package:sufler/import/structure/headings.dart';
import 'package:sufler/import/styled_line.dart';

/// The speaker dictionary of a play: its cast list with its groups, plus
/// the recurring headings after it. Also returns where the cast list ends.
(Cast, int) buildCast(List<StyledLine> lines) {
  final (names, end, groups) = castList([for (final l in lines) l.text]);
  final cast = Cast();
  for (final (i, name) in names.indexed) {
    if (cast.resolve(name, record: false)?.name != name) cast.add(name, i);
  }
  for (final g in groups) {
    cast.addGroup(g.name, g.members);
  }
  inferCast(cast, lines, end + 1);
  return (cast, end);
}

/// Adds recurring heading-shaped lines (2+ times, each followed by text)
/// that the cast list does not already cover.
void inferCast(Cast cast, List<StyledLine> lines, int from) {
  final counts = <String, int>{};
  final first = <String, int>{};
  for (var i = from; i < lines.length; i++) {
    if (lines[i].tint != Tint.normal) continue;
    final (name, _) = splitTrailingDirection(lines[i].text);
    if (!headingShaped(name, 4)) continue;
    final next = lines.skip(i + 1).map((l) => l.text.trim());
    final text = next.firstWhere((t) => t.isNotEmpty, orElse: () => '');
    if (text.isEmpty || headingParts(text) != null) continue;
    counts[name] = (counts[name] ?? 0) + 1;
    first.putIfAbsent(name, () => i);
  }
  final recurring = counts.keys.where((k) => counts[k]! >= 2).toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  for (final name in recurring) {
    for (final part in headingParts(name)!) {
      if (cast.resolve(part) == null) cast.add(part, 1000 + first[name]!);
    }
  }
}

/// Whether [text] can be a speaker heading of at most [maxWords] words.
bool headingShaped(String text, int maxWords) =>
    headingParts(text, maxWords: maxWords) != null &&
    !isSceneHeading(text) &&
    songTitle(text) == null;
