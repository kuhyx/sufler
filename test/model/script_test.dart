import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

Script _sample() => const Script(
  id: 'abc',
  title: 'Sztuka',
  source: 'sztuka.odt',
  characters: [
    Character(id: 'wilk', name: 'Wilk', aliases: ['Wlik']),
    Character(id: 'lis', name: 'Lis'),
  ],
  scenes: [Section(id: 'scena-1', title: 'Scena 1', start: 0, end: 4)],
  songs: [
    Section(id: 'piosenka-lisa', title: 'Piosenka Lisa', start: 3, end: 4),
  ],
  lines: [
    ScriptLine(
      index: 0,
      speakers: [],
      text: 'Scena 1',
      kind: LineKind.heading,
      sceneId: 'scena-1',
    ),
    ScriptLine(
      index: 1,
      speakers: ['lis'],
      text: 'Dzień dobry.',
      kind: LineKind.dialogue,
      sceneId: 'scena-1',
      directions: ['(kłania się)'],
    ),
    ScriptLine(
      index: 2,
      speakers: ['wilk', 'lis'],
      text: 'Witaj!',
      kind: LineKind.dialogue,
      sceneId: 'scena-1',
    ),
    ScriptLine(
      index: 3,
      speakers: [],
      text: 'La la',
      kind: LineKind.song,
      sceneId: 'scena-1',
      songId: 'piosenka-lisa',
    ),
    ScriptLine(
      index: 4,
      speakers: [],
      text: 'Lu lu',
      kind: LineKind.song,
      sceneId: 'scena-1',
      songId: 'piosenka-lisa',
    ),
  ],
);

void main() {
  test('Script survives a JSON round trip unchanged', () {
    final script = _sample();
    final text = jsonEncode(script.toJson());
    final back = Script.fromJson(jsonDecode(text) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), text);
  });

  test('text with no letters or digits is never spoken', () {
    ScriptLine line(String text) => ScriptLine(
      index: 0,
      speakers: const ['lis'],
      text: text,
      kind: LineKind.dialogue,
    );
    for (final text in ['', '...', '…', '(…)', ' – ! ', '/.../']) {
      expect(line(text).isSpoken, isFalse, reason: text);
    }
    for (final text in ['Tak.', '7', 'Żółć…', '...a']) {
      expect(line(text).isSpoken, isTrue, reason: text);
    }
  });

  test('roles select lines by speaker or by song, never headings', () {
    final lines = _sample().lines;
    final wolf = {Role.character('wilk')};
    expect(
      [
        for (final l in lines)
          if (isMine(l, wolf)) l.index,
      ],
      [2],
    );
    final song = {Role.song('piosenka-lisa')};
    expect(
      [
        for (final l in lines)
          if (isMine(l, song)) l.index,
      ],
      [3, 4],
    );
    expect(Role.parse('song:piosenka-lisa'), const Role.song('piosenka-lisa'));
    expect(
      Role.parse(const Role.character('wilk').toString()),
      const Role.character('wilk'),
    );
  });

  test('a group role owns lines its members say together', () {
    final lines = _sample().lines;
    final pair = Role.group(['wilk', 'lis']);
    expect(pair.toString(), 'group:lis+wilk');
    expect(pair.members, ['lis', 'wilk']);
    expect(Role.parse('group:lis+wilk'), pair);
    expect(Role.group(['lis', 'wilk', 'lis']), pair);
    expect(
      [
        for (final l in lines)
          if (isMine(l, {pair})) l.index,
      ],
      [2],
    );
    // The chorus: lines with no speaker.
    final chorus = Role.group(const []);
    expect(chorus.toString(), 'group:');
    expect(Role.parse('group:'), chorus);
    expect(chorus.members, isEmpty);
    expect(
      [
        for (final l in lines)
          if (isMine(l, {chorus})) l.index,
      ],
      [3, 4],
    );
    expect(pair.isSong, isFalse);
  });
}
