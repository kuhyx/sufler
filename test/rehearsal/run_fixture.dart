import 'package:sufler/model/script.dart';

import 'fixture.dart';

export 'fixture.dart' show elf, wolf;

ScriptLine _l(
  int i,
  LineKind kind,
  List<String> who,
  String text, {
  String scene = 'scena-1',
  String? song,
}) => ScriptLine(
  index: i,
  speakers: who,
  text: text,
  kind: kind,
  sceneId: scene,
  songId: song,
);

/// Synthetic play with a three-line monologue (2, 4, 5: a direction in
/// between) and a three-verse song (8-10) of the Wolf, each cued by a
/// partner line; 7 is a lone own line just before the song.
Script runScript() => Script(
  id: 'run123',
  title: 'Monolog testowy',
  source: 'run.txt',
  characters: const [
    Character(id: wolf, name: 'Piaskowy Wilk'),
    Character(id: elf, name: 'Błystek'),
  ],
  scenes: const [Section(id: 'scena-1', title: 'Scena 1', start: 0, end: 11)],
  songs: const [
    Section(id: 'piosenka-wilka', title: 'Piosenka Wilka', start: 8, end: 10),
  ],
  lines: [
    _l(0, LineKind.heading, [], 'Scena 1'),
    _l(1, LineKind.dialogue, [elf], 'Witaj, Wilku.'),
    _l(2, LineKind.dialogue, [wolf], 'Raz dwa trzy cztery.'),
    _l(3, LineKind.direction, [], 'Wilk wstaje.'),
    _l(4, LineKind.dialogue, [wolf], 'Pięć sześć.'),
    _l(5, LineKind.dialogue, [wolf], 'Siedem osiem dziewięć dziesięć.'),
    _l(6, LineKind.dialogue, [elf], 'Brawo.'),
    _l(7, LineKind.dialogue, [wolf], 'Teraz piosenka.'),
    _l(8, LineKind.song, [wolf], 'Ala ma kota', song: 'piosenka-wilka'),
    _l(9, LineKind.song, [wolf], 'Kot ma Alę', song: 'piosenka-wilka'),
    _l(10, LineKind.song, [wolf], 'Oboje mają psa', song: 'piosenka-wilka'),
    _l(11, LineKind.dialogue, [elf], 'Koniec.'),
  ],
);
