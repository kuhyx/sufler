/// Which cards a script yields for a set of roles: cue on the front, the
/// actor's own line (and the assistant's notes on it) on the back.
library;

import 'dart:typed_data';

import 'package:sufler/anki/anki_deck.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

export 'package:sufler/anki/anki_deck.dart';

/// Label for an unattributed line (a chorus lyric with no named singers).
const String chorusLabel = 'Chór';

/// Label prefix for a cue the actor speaks themselves.
const String yoursLabel = 'Ty';

/// Cue shown for the very first spoken line, which has nothing before it.
const String startLabel = '(początek)';

/// Anki media file name of the clip for line [index] of [scriptId].
String cueMediaName(String scriptId, int index) =>
    'sufler-$scriptId-$index.ogg';

/// Builds the deck for [roles]: one card per spoken line the actor owns.
///
/// The cue is the previous *spoken* line (stage directions and headings are
/// skipped), even when it is the actor's own; then it is labelled as theirs.
/// Each lyric line is its own [ScriptLine], so songs yield a card per line.
/// Cue audio comes from [audio] when it holds a clip for the cue line.
/// [notes] (line index -> notes) go on the back under the line.
AnkiDeck buildDeck(
  Script script,
  Set<Role> roles, {
  AudioPack? audio,
  Map<int, List<LineNote>> notes = const {},
}) {
  final names = {for (final c in script.characters) c.id: c.name};
  final scenes = {for (final s in script.scenes) s.id: s};
  final cards = <AnkiCard>[];
  final media = <String, Uint8List>{};
  ScriptLine? cue;
  for (final line in script.lines) {
    if (!line.isSpoken) continue;
    if (isMine(line, roles)) {
      final clip = cue == null ? null : audio?.clip(cue.index);
      final sound = clip == null ? null : cueMediaName(script.id, cue!.index);
      if (sound != null) media[sound] = clip!;
      final scene = scenes[line.sceneId];
      cards.add(
        AnkiCard(
          key: '${script.id}|${line.index}',
          deck: scene == null
              ? script.title
              : '${script.title}::${scene.title}',
          front: cue == null
              ? '$startLabel ${_html(_sectionTitle(script, line))}'
              : _cueHtml(cue, _speaker(cue, names, roles), sound),
          back: _html(line.text) + _notesHtml(notes[line.index]),
        ),
      );
    }
    cue = line;
  }
  return AnkiDeck(title: script.title, cards: cards, media: media);
}

String _notesHtml(List<LineNote>? notes) => notes == null || notes.isEmpty
    ? ''
    : '<hr>${[for (final n in notes) _noteHtml(n)].join('<br>')}';

String _noteHtml(LineNote n) => '<b>${_html(n.about)}</b>: ${_html(n.text)}';

String _cueHtml(ScriptLine cue, String speaker, String? sound) =>
    '<b>${_html(speaker)}:</b> ${_html(cue.text)}'
    '${sound == null ? '' : ' [sound:$sound]'}';

String _speaker(ScriptLine line, Map<String, String> names, Set<Role> roles) {
  final who = line.speakers.isEmpty
      ? chorusLabel
      : [for (final id in line.speakers) names[id] ?? id].join(', ');
  return isMine(line, roles) ? '$yoursLabel ($who)' : who;
}

/// Title of the section the first line opens: its song, else its scene,
/// else the play itself.
String _sectionTitle(Script script, ScriptLine line) {
  for (final s in [...script.songs, ...script.scenes]) {
    if (s.id == line.songId || s.id == line.sceneId) return s.title;
  }
  return script.title;
}

/// Escapes [text] for an Anki HTML field; line breaks become `<br>`.
String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\n', '<br>');
