import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

/// Copy of [s] with only [lines] and [characters] replaced.
Script _with(
  Script s, {
  List<ScriptLine>? lines,
  List<Character>? characters,
}) => Script(
  id: s.id,
  title: s.title,
  source: s.source,
  characters: characters ?? s.characters,
  scenes: s.scenes,
  songs: s.songs,
  lines: lines ?? s.lines,
);

/// Correction: set line [index]'s [speakers] and/or [kind].
Script editLine(
  Script s,
  int index, {
  List<String>? speakers,
  LineKind? kind,
}) => _with(
  s,
  lines: s.lines
      .map(
        (l) =>
            l.index == index ? l.copyWith(speakers: speakers, kind: kind) : l,
      )
      .toList(),
);

/// Correction: character [from] is really [into] (a misspelling or alias).
/// Every line of [from] moves to [into]; [from]'s name and aliases become
/// aliases of [into].
Script mergeCharacter(Script s, {required String from, required String into}) {
  if (from == into) return s;
  final gone = s.characters.firstWhere((c) => c.id == from);
  return _with(
    s,
    characters: [
      for (final c in s.characters)
        if (c.id == into)
          Character(
            id: c.id,
            name: c.name,
            aliases: [...c.aliases, gone.name, ...gone.aliases],
          )
        else if (c.id != from)
          c,
    ],
    lines: s.lines
        .map(
          (l) => l.speakers.contains(from)
              ? l.copyWith(
                  speakers: l.speakers
                      .map((id) => id == from ? into : id)
                      .toSet()
                      .toList(),
                )
              : l,
        )
        .toList(),
  );
}

/// Picked roles after merging character [from] into [into].
Set<Role> renameRole(
  Set<Role> roles, {
  required String from,
  required String into,
}) => roles
    .map((r) => !r.isSong && r.id == from ? Role.character(into) : r)
    .toSet();

/// A role the actor can pick, with how many spoken lines it owns.
typedef RoleOption = ({Role role, String label, int count});

/// Every character, then every song, with spoken-line counts.
List<RoleOption> roleOptions(Script s) {
  int count(Role r) => s.lines.where((l) => l.isSpoken && r.owns(l)).length;
  return [
    for (final c in s.characters)
      (
        role: Role.character(c.id),
        label: c.name,
        count: count(Role.character(c.id)),
      ),
    for (final song in s.songs)
      (
        role: Role.song(song.id),
        label: song.title,
        count: count(Role.song(song.id)),
      ),
  ];
}
