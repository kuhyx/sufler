import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';

/// What the actor plays: a character, or a whole song (sung by them).
@immutable
class Role {
  /// A character role.
  const new character(this.id) : isSong = false;

  /// A song role: every line of the song is the actor's.
  const new song(this.id) : isSong = true;

  /// Parses `character:<id>` / `song:<id>`.
  factory parse(String value) {
    final i = value.indexOf(':');
    final kind = value.substring(0, i);
    final id = value.substring(i + 1);
    return kind == 'song' ? Role.song(id) : Role.character(id);
  }

  /// Character id or song section id.
  final String id;

  /// True for a song role.
  final bool isSong;

  /// Whether [line] belongs to the actor under this role.
  bool owns(ScriptLine line) =>
      isSong ? line.songId == id : line.speakers.contains(id);

  @override
  String toString() => '${isSong ? 'song' : 'character'}:$id';

  @override
  bool operator ==(Object other) =>
      other is Role && other.id == id && other.isSong == isSong;

  @override
  int get hashCode => Object.hash(id, isSong);
}

/// Whether [line] is the actor's under any of [roles].
bool isMine(ScriptLine line, Set<Role> roles) =>
    line.isSpoken && roles.any((r) => r.owns(line));
