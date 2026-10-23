import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';

/// What kind of thing a [Role] picks.
enum RoleKind {
  /// One character: their lines, alone or together with others.
  character,

  /// A whole song: every lyric line of it.
  song,

  /// A group of speakers: every line they say together.
  group,
}

/// What the actor plays: a character, a whole song, or a group.
@immutable
class Role {
  /// A character role.
  const new character(this.id) : kind = RoleKind.character;

  /// A song role: every line of the song is the actor's.
  const new song(this.id) : kind = RoleKind.song;

  /// A group role over member ids joined by `+`; see [group].
  const new _group(this.id) : kind = RoleKind.group;

  /// A group role: every line whose speakers include all of [members]. No
  /// members = the chorus, i.e. unattributed lines ([ScriptLine.speakers]
  /// empty).
  factory group(Iterable<String> members) =>
      Role._group((members.toSet().toList()..sort()).join('+'));

  /// Parses `character:<id>` / `song:<id>` / `group:<id>+<id>…`.
  factory parse(String value) {
    final i = value.indexOf(':');
    final id = value.substring(i + 1);
    return switch (value.substring(0, i)) {
      'song' => Role.song(id),
      'group' => Role._group(id),
      _ => Role.character(id),
    };
  }

  /// Character id, song section id, or the group's sorted member ids
  /// joined by `+` (empty for the chorus).
  final String id;

  /// What this role picks.
  final RoleKind kind;

  /// True for a song role.
  bool get isSong => kind == RoleKind.song;

  /// Member ids of a group role (empty for the chorus and other kinds).
  List<String> get members =>
      kind != RoleKind.group || id.isEmpty ? const [] : id.split('+');

  /// Whether [line] belongs to the actor under this role.
  bool owns(ScriptLine line) => switch (kind) {
    RoleKind.song => line.songId == id,
    RoleKind.character => line.speakers.contains(id),
    RoleKind.group =>
      id.isEmpty
          ? line.speakers.isEmpty
          : members.every(line.speakers.contains),
  };

  @override
  String toString() => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is Role && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

/// Whether [line] is the actor's under any of [roles].
bool isMine(ScriptLine line, Set<Role> roles) =>
    line.isSpoken && roles.any((r) => r.owns(line));
