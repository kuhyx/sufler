import 'package:sufler/model/script.dart';

/// Synthetic play used across rehearsal, storage and UI tests (never a real
/// script: plays are copyrighted).
const wolf = 'piaskowy-wilk';
const elf = 'blystek';

ScriptLine _l(
  int i,
  LineKind kind,
  List<String> who,
  String text, {
  String? scene,
  String? song,
}) => ScriptLine(
  index: i,
  speakers: who,
  text: text,
  kind: kind,
  sceneId: scene,
  songId: song,
);

/// Builds the fixture script.
Script fixtureScript() => Script(
  id: 'abc123',
  title: 'Krasnale testowe',
  source: 'test.txt',
  characters: const [
    Character(id: wolf, name: 'Piaskowy Wilk'),
    Character(id: elf, name: 'Błystek'),
  ],
  scenes: const [
    Section(id: 'scena-1', title: 'Scena 1', start: 0, end: 5),
    Section(id: 'scena-2', title: 'Scena 2', start: 6, end: 10),
  ],
  songs: const [Section(id: 'piosenka', title: 'Piosenka', start: 7, end: 9)],
  lines: [
    _l(0, LineKind.heading, [], 'Scena 1', scene: 'scena-1'),
    _l(1, LineKind.dialogue, [elf], 'Dzień dobry, Wilku!', scene: 'scena-1'),
    _l(
      2,
      LineKind.dialogue,
      [wolf],
      'Piaskowe Wilki nie jedzą Krasnali!',
      scene: 'scena-1',
    ),
    _l(3, LineKind.direction, [], 'Wilk siada.', scene: 'scena-1'),
    _l(4, LineKind.dialogue, [wolf], 'Naprawdę.', scene: 'scena-1'),
    _l(5, LineKind.dialogue, [elf], 'No dobrze.', scene: 'scena-1'),
    _l(6, LineKind.heading, [], 'Scena 2', scene: 'scena-2'),
    _l(7, LineKind.song, [], 'La la la', scene: 'scena-2', song: 'piosenka'),
    _l(
      8,
      LineKind.song,
      [elf],
      'Śpiewam ja',
      scene: 'scena-2',
      song: 'piosenka',
    ),
    _l(9, LineKind.song, [], 'Hej hej', scene: 'scena-2', song: 'piosenka'),
    _l(10, LineKind.dialogue, [wolf, elf], 'Koniec!', scene: 'scena-2'),
  ],
);
