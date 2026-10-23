import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

/// A group speaker the actor can join: an ensemble heading ("Wszyscy"),
/// the unattributed chorus, or a set of characters that keep speaking
/// together (the krasnale singing as one).
typedef GroupOption = ({
  Role role,
  String label,
  int count,

  /// Character ids that belong to the group (suggested to its members).
  Set<String> members,
});

/// Headings that mean "everyone on stage" or a named ensemble.
final _ensemble = RegExp(
  '^(wszyscy|wszystkie|razem|chór|chor|chórem|zespół|tłum|krasnale|'
  r'krasnoludki|krasnoludy)\b',
  caseSensitive: false,
  unicode: true,
);

/// Whether character [c] is an ensemble rather than one person.
bool isEnsemble(Script s, Character c) =>
    _ensemble.hasMatch(c.name.trim()) || _pluralOf(s, c).length >= 2;

/// Ensemble headings that are everyone, not a named subset.
final _everyone = RegExp(
  r'^(wszyscy|wszystkie|razem|chór|chor|chórem|zespół|tłum)\b',
  caseSensitive: false,
  unicode: true,
);

/// Characters whose first word shares [c]'s stem ("Śnieżynki" ->
/// "Śnieżynka 1", "Śnieżynka 2"): all but the last 2 letters, at least 4.
Set<String> _pluralOf(Script s, Character c) {
  final word = c.name.trim().toLowerCase().split(' ').first;
  if (c.name.trim().contains(' ') || word.length < 6) return const {};
  final stem = word.substring(0, word.length - 2);
  return {
    for (final o in s.characters)
      if (o.id != c.id &&
          o.name.toLowerCase().startsWith(stem) &&
          o.name.trim().contains(' '))
        o.id,
  };
}

/// Every group speaker of [s], with spoken-line counts.
List<GroupOption> groupOptions(Script s) {
  int count(Role r) => s.lines.where((l) => isMine(l, {r})).length;
  final everyone = {for (final c in s.characters) c.id};
  final out = <GroupOption>[];
  for (final c in s.characters.where((c) => isEnsemble(s, c))) {
    final role = Role.character(c.id);
    final plural = _pluralOf(s, c);
    out.add((
      role: role,
      label: c.name,
      count: count(role),
      members: _everyone.hasMatch(c.name.trim()) ? everyone : plural,
    ));
  }
  final ensembleIds = {for (final o in out) o.role.id};
  final sets = <String, int>{};
  for (final l in s.lines.where((l) => l.isSpoken)) {
    final ids = l.speakers.where((id) => !ensembleIds.contains(id)).toSet();
    if (ids.length < 3) continue;
    final key = Role.group(ids).id;
    sets[key] = (sets[key] ?? 0) + 1;
  }
  String name(String id) => s.characters.firstWhere((c) => c.id == id).name;
  for (final e in sets.entries.where((e) => e.value >= 2)) {
    final role = Role.parse('group:${e.key}');
    out.add((
      role: role,
      label: role.members.map(name).join(', '),
      count: count(role),
      members: role.members.toSet(),
    ));
  }
  final chorus = Role.group(const []);
  final unattributed = count(chorus);
  if (unattributed > 0) {
    out.add((
      role: chorus,
      label: 'Chór (kwestie bez przypisania)',
      count: unattributed,
      members: const {},
    ));
  }
  return out;
}

/// Groups to pre-tick for someone playing [characters].
Set<Role> suggestedGroups(List<GroupOption> groups, Set<String> characters) => {
  for (final g in groups)
    if (g.members.any(characters.contains)) g.role,
};

/// Spoken lines [role] adds on top of what [picked] already owns.
int extraLines(Script s, Role role, Set<Role> picked) => s.lines
    .where((l) => isMine(l, {role}) && !isMine(l, picked.difference({role})))
    .length;
