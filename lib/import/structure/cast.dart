import 'dart:math' as math;

import 'package:sufler/import/structure/slug.dart';
import 'package:sufler/model/script.dart';

/// A character being collected, with the spellings folded into it.
class CastMember {
  /// Creates a member.
  CastMember(this.id, this.name, this.order);

  /// Slug id.
  final String id;

  /// Canonical name.
  final String name;

  /// Sort key: cast-list position, or first appearance after the cast.
  int order;

  /// Other spellings seen in headings.
  final List<String> aliases = [];

  /// The model form.
  Character toCharacter() =>
      Character(id: id, name: name, aliases: List.of(aliases));
}

/// Optimal-string-alignment distance (Levenshtein + adjacent swaps), so
/// "Piaksowy" is one edit from "Piaskowy".
int osaDistance(String a, String b) {
  final d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1);
      v = math.min(v, d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, d[i - 2][j - 2] + 1);
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// The speaker dictionary: resolves heading spellings to characters.
class Cast {
  final List<CastMember> _members = [];
  final SlugRegistry _ids = SlugRegistry();

  /// Members in display order.
  List<CastMember> get members =>
      [..._members]..sort((a, b) => a.order.compareTo(b.order));

  /// Whether no character is known yet.
  bool get isEmpty => _members.isEmpty;

  /// Adds a new character called [name].
  CastMember add(String name, int order) {
    final m = CastMember(_ids.take(name), _norm(name), order);
    _members.add(m);
    return m;
  }

  /// The member [part] names: exactly, by an alias, as the unique first
  /// word / prefix of a name, or within 2 typos (names of 6+ letters whose
  /// digits agree). A non-exact match is recorded as an alias when
  /// [record] is set.
  CastMember? resolve(String part, {bool record = true}) {
    final p = _norm(part);
    final lower = p.toLowerCase();
    for (final m in _members) {
      if (m.name.toLowerCase() == lower ||
          m.aliases.any((a) => a.toLowerCase() == lower)) {
        return m;
      }
    }
    final match = _prefixMatch(lower) ?? _fuzzyMatch(lower);
    if (record && match != null && !match.aliases.contains(p)) {
      match.aliases.add(p);
    }
    return match;
  }

  CastMember? _prefixMatch(String lower) {
    if (lower.length < 3 || _digits(lower).isNotEmpty) return null;
    final hits = _members
        .where((m) => m.name.toLowerCase().startsWith('$lower '))
        .toList();
    return hits.length == 1 ? hits.single : null;
  }

  CastMember? _fuzzyMatch(String lower) {
    if (lower.length < 6) return null;
    CastMember? best;
    var bestD = 3;
    var tie = false;
    for (final m in _members) {
      final name = m.name.toLowerCase();
      if (name.length < 6 || _digits(name) != _digits(lower)) continue;
      final d = osaDistance(lower, name);
      if (d < bestD) {
        (best, bestD, tie) = (m, d, false);
      } else if (d == bestD && m != best) {
        tie = true;
      }
    }
    return tie ? null : best;
  }

  /// The member an inflected phrase names ("Piaskowego Wilka", "macochy"):
  /// same word count, each word sharing all but its last 2 letters.
  CastMember? inflected(String phrase) {
    final words = _norm(phrase).toLowerCase().split(' ');
    bool stem(String a, String b) {
      var i = 0;
      while (i < a.length && i < b.length && a[i] == b[i]) {
        i++;
      }
      return i >= 3 && i >= math.min(a.length, b.length) - 2;
    }

    final hits = _members.where((m) {
      final name = m.name.toLowerCase().split(' ');
      if (name.length != words.length) return false;
      for (var i = 0; i < name.length; i++) {
        if (!stem(name[i], words[i])) return false;
      }
      return true;
    }).toList();
    return hits.length == 1 ? hits.single : null;
  }

  /// Members named (by name, alias or distinctive first word) in [text],
  /// in order of mention.
  List<String> mentionedIn(String text) {
    final found = <(int, String)>[];
    for (final m in _members) {
      final first = m.name.split(' ').first;
      final names = {m.name, ...m.aliases, if (first.length >= 3) first};
      for (final n in names) {
        final re = RegExp(
          '(?<!\\p{L})${RegExp.escape(n)}(?!\\p{L})',
          unicode: true,
        );
        final hit = re.firstMatch(text);
        if (hit != null) {
          found.add((hit.start, m.id));
          break;
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }
}
