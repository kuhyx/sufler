/// Who sings a song line: songs named after a character or a cast group,
/// and singer tags ("R.", "L.", "Razem") inside a song.
library;

import 'package:sufler/import/structure/cast.dart';
import 'package:sufler/import/structure/headings.dart';

final _songWord = RegExp(r'^Piosenka\s*|["„”“]');
final _everyone = RegExp(r'^(razem|wszyscy|chór|chor)$', caseSensitive: false);
final _initial = RegExp(r'^\p{Lu}\p{Ll}?\.$', unicode: true);

/// The singers a song title names: one character ("Piosenka Macochy") or
/// every member of a cast-list group ("Piosenka Krasnali 2" for the group
/// "Krasnale"); null when it names neither.
List<String>? titleSingers(Cast cast, String title) {
  final phrase = title
      .replaceAll(_songWord, '')
      .replaceFirst(RegExp(r'\s+\d+$'), '')
      .trim();
  if (phrase.isEmpty) return null;
  final named = cast.inflected(phrase);
  return named == null ? cast.group(phrase) : [named.id];
}

/// The singers a tag line inside a song sets, or null when [text] is not a
/// tag. "Razem" / "Wszyscy" / "Chór" mean [all] singers of the song; an
/// initial ("R.") is the one singer whose name starts with it, looked up
/// in [all] and then among the [scene] speakers. An initial matching
/// several or none of them is unattributed. Parts may be joined ("R. i L.").
List<String>? singerTag(
  String text,
  Cast cast,
  List<String> all,
  Iterable<String> scene,
) {
  final t = squash(text).replaceFirst(RegExp(r'\s*:$'), '');
  if (t.isEmpty) return null;
  final ids = <String>[];
  for (final part in t.split(RegExp(r'\s*[,+&]\s*|\s+i\s+'))) {
    if (_everyone.hasMatch(part)) {
      ids.addAll(all);
    } else if (_initial.hasMatch(part)) {
      final letters = part.substring(0, part.length - 1).toLowerCase();
      final hit =
          _byInitial(cast, all, letters) ?? _byInitial(cast, scene, letters);
      if (hit != null && hit.isNotEmpty) ids.add(hit);
    } else {
      return null;
    }
  }
  return ids.toSet().toList();
}

/// The id in [ids] whose name starts with [letters]: null when none,
/// '' (no one) when several do.
String? _byInitial(Cast cast, Iterable<String> ids, String letters) {
  final names = {for (final m in cast.members) m.id: m.name.toLowerCase()};
  final hits = ids.toSet().where(
    (id) => names[id]?.startsWith(letters) ?? false,
  );
  if (hits.isEmpty) return null;
  return hits.length == 1 ? hits.single : '';
}
