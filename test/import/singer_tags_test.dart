// Who sings a song line: singer tags inside a song ("R.", "L.", "Razem")
// and songs named after a cast-list group ("Piosenka Leśnych").
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/import/structure/cast.dart';
import 'package:sufler/import/structure/singers.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/script.dart';

const _n = Tint.normal;
const _r = Tint.song;

final _play = <(Tint, String)>[
  (_n, 'Bohaterowie:'),
  (_n, '1. Leśni:'),
  (_n, '- Sowa'),
  (_n, '- Sokół'),
  (_n, '- Nietoperz'),
  (_n, '2. "Ogrodowi" goście'),
  (_n, '- Lis i Róża'),
  (_n, 'Scena 1'),
  (_r, 'Róża i Lis śpiewają piosenkę'),
  (_r, 'R.'),
  (_r, 'Kolce mam ostre'),
  (_r, 'I płatki czerwone'),
  (_r, 'L.'),
  (_r, 'Oswój mnie proszę'),
  (_r, 'Razem'),
  (_r, 'Mowa to kłopot'),
  (_n, 'Lis'),
  (_n, 'Pięknie.'),
  (_n, 'Scena 2'),
  (_n, 'Wszyscy'),
  (_n, 'Hura!'),
  (_n, 'Sowa'),
  (_n, 'Zaczynamy.'),
  (_n, 'Piosenka Leśnych'),
  (_r, 'Las szumi nocą'),
  (_r, 'S.'),
  (_r, 'Pohukuję cicho'),
  (_r, 'Wszyscy'),
  (_r, 'Hu hu hu'),
  (_n, 'Wszyscy'),
  (_n, 'Brawo!'),
  (_n, 'Nietoperz'),
  (_n, 'Coś.'),
  (_n, 'Piosenka Sowy'),
  (_r, 'Sowa śpiewa sama'),
  (_n, 'Piosenka Wieczorna'),
  (_r, 'Wieczór nadchodzi'),
  (_r, 'S.'),
  (_r, 'Huczę po cichu'),
  (_r, 'Chór:'),
  (_r, 'Dobranoc'),
  (_n, 'Scena 3'),
  (_n, 'Sokół'),
  (_n, 'Kra.'),
  (_n, 'Piosenka Leśnych 2'),
  (_r, 'Wszyscy razem'),
];

void main() {
  late Script s;
  setUp(
    () => s = buildScript(
      [for (final (t, x) in _play) StyledLine(x, tint: t)],
      id: 'x',
      source: 'synthetic.odt',
    ),
  );
  List<String> sungBy(String text) =>
      s.lines.singleWhere((l) => l.text == text && l.isSpoken).speakers;
  ScriptLine tag(String text, int nth) =>
      s.lines.where((l) => l.directions.contains(text)).elementAt(nth);

  test('R. / L. / Razem set the singers of the duet lines that follow', () {
    expect(sungBy('Kolce mam ostre'), ['roza']);
    expect(sungBy('I płatki czerwone'), ['roza']);
    expect(sungBy('Oswój mnie proszę'), ['lis']);
    expect(sungBy('Mowa to kłopot'), ['roza', 'lis']);
  });

  test('tag lines are unspoken directions, never a song title', () {
    for (final t in ['R.', 'L.', 'Razem', 'S.', 'Chór:']) {
      final line = tag(t, 0);
      expect(line.kind, LineKind.direction, reason: t);
      expect(line.text, isEmpty, reason: t);
      expect(line.isSpoken, isFalse, reason: t);
    }
    final duet = s.songs.firstWhere((x) => x.title.startsWith('♪ '));
    expect(duet.title, '♪ Kolce mam ostre');
    expect(s.lines[duet.start].text, 'Kolce mam ostre');
    // The leading tag sits before the section, like the intro; later tags
    // stay inside it.
    expect(tag('R.', 0).songId, isNull);
    expect(tag('L.', 0).songId, duet.id);
    expect(s.songs.where((x) => x.title.contains('R.')), isEmpty);
  });

  test('Wszyscy / Chór in a song means every singer of it', () {
    const forest = ['sowa', 'sokol', 'nietoperz'];
    expect(sungBy('Hu hu hu'), forest);
    expect(tag('Wszyscy', 0).kind, LineKind.direction);
    // Outside songs "Wszyscy" is still a speaker heading.
    expect(sungBy('Brawo!'), ['wszyscy']);
    expect(sungBy('Dobranoc'), ['nietoperz', 'sowa']);
  });

  test('an initial shared by two singers leaves the lines unattributed', () {
    expect(sungBy('Pohukuję cicho'), isEmpty);
  });

  test('an initial no singer has falls back to the scene speakers', () {
    // Sung by Nietoperz (last speaker); Sowa is the only S. in the scene.
    expect(sungBy('Wieczór nadchodzi'), ['nietoperz']);
    expect(sungBy('Huczę po cichu'), ['sowa']);
  });

  test('a song named after a cast group is sung by all its members', () {
    const forest = ['sowa', 'sokol', 'nietoperz'];
    expect(sungBy('Las szumi nocą'), forest);
    // A trailing number does not hide the group; a lyric with "razem" in
    // it is not a tag.
    expect(sungBy('Wszyscy razem'), forest);
    // A title naming one character keeps that character.
    expect(sungBy('Sowa śpiewa sama'), ['sowa']);
  });

  test('singerTag: joined forms, unknown initials, non-tags', () {
    final cast = Cast()
      ..add('Róża', 0)
      ..add('Lis', 1);
    expect(singerTag('R. i L.', cast, ['roza', 'lis'], []), ['roza', 'lis']);
    expect(singerTag('Razem:', cast, ['lis'], []), ['lis']);
    expect(singerTag('X.', cast, ['roza'], ['lis']), isEmpty);
    expect(singerTag('Kto?', cast, ['roza'], []), isNull);
    expect(singerTag('R. i ktoś', cast, ['roza'], []), isNull);
    expect(titleSingers(cast, 'Piosenka'), isNull);
    expect(titleSingers(cast, 'Piosenka Lisa 3'), ['lis']);
  });
}
