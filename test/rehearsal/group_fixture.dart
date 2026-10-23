import 'package:sufler/model/script.dart';

/// Synthetic play with group speakers: an ensemble heading ("Wszyscy"), a
/// plural heading over numbered members ("Śnieżynki"), a trio that sings
/// together, and an unattributed chorus lyric.
ScriptLine _l(int i, List<String> who, String text, {String? song}) =>
    ScriptLine(
      index: i,
      speakers: who,
      text: text,
      kind: song == null ? LineKind.dialogue : LineKind.song,
      sceneId: 'scena-1',
      songId: song,
    );

/// Builds the group fixture.
Script groupScript() => Script(
  id: 'grp',
  title: 'Grupy testowe',
  source: 'grupy.txt',
  characters: const [
    Character(id: 'ala', name: 'Ala'),
    Character(id: 'bolek', name: 'Bolek'),
    Character(id: 'cela', name: 'Cela'),
    Character(id: 'wilk', name: 'Wilk'),
    Character(id: 'wszyscy', name: 'Wszyscy'),
    Character(id: 'sniezynki', name: 'Śnieżynki'),
    Character(id: 'sniezynka-1', name: 'Śnieżynka 1'),
    Character(id: 'sniezynka-2', name: 'Śnieżynka 2'),
  ],
  scenes: const [Section(id: 'scena-1', title: 'Scena 1', start: 0, end: 9)],
  songs: const [Section(id: 'hej', title: 'Piosenka Hej', start: 2, end: 5)],
  lines: [
    const ScriptLine(
      index: 0,
      speakers: [],
      text: 'Scena 1',
      kind: LineKind.heading,
      sceneId: 'scena-1',
    ),
    _l(1, ['ala'], 'Cześć wszystkim'),
    _l(2, ['ala', 'bolek', 'cela'], 'Hej ho idziemy', song: 'hej'),
    _l(3, ['ala', 'bolek', 'cela'], 'Hej ha śpiewamy', song: 'hej'),
    _l(4, ['ala', 'bolek', 'cela'], 'Do domu wracamy', song: 'hej'),
    _l(5, [], 'La la la', song: 'hej'),
    _l(6, ['wszyscy'], 'Brawo!'),
    _l(7, ['sniezynki'], 'Zima!'),
    _l(8, ['wilk'], 'Auu'),
    _l(9, ['ala', 'bolek', 'cela', 'wilk'], 'Razem!'),
  ],
);
