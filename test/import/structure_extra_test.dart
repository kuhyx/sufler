import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/script.dart';

Script _build(List<StyledLine> lines) =>
    buildScript(lines, id: 'x', source: 'sztuka.pdf');

void main() {
  final cast = [
    const StyledLine('Bohaterowie:'),
    const StyledLine('- Kot Łatek'),
    const StyledLine('- Stary Zegar'),
    const StyledLine('Scena 2'),
  ];

  test('a song title naming a character (inflected) picks the singer', () {
    final s = _build([
      ...cast,
      const StyledLine('Stary Zegar'),
      const StyledLine('Posłuchajcie.'),
      const StyledLine('"Piosenka Kota Łatka"'),
      const StyledLine('Miau miau', tint: Tint.song),
    ]);
    final lyric = s.lines.last;
    expect(lyric.kind, LineKind.song);
    expect(lyric.speakers, ['kot-latek']);
    expect(s.title, 'sztuka');
  });

  test('soft-wrapped PDF lines join with a space, paragraphs with \\n', () {
    final s = _build([
      ...cast,
      const StyledLine('Kot Łatek'),
      const StyledLine('Pierwsza część zdania', wraps: true),
      const StyledLine('i jego koniec.'),
      const StyledLine('Nowy akapit.'),
    ]);
    expect(
      s.lines.last.text,
      'Pierwsza część zdania i jego koniec.\nNowy akapit.',
    );
  });

  test('a direction running over lines never yields a heading', () {
    final s = _build([
      ...cast,
      const StyledLine('Kot Łatek'),
      const StyledLine('Patrzcie! (z szafy wychodzi'),
      const StyledLine('Stary Zegar)'),
      const StyledLine('Stary Zegar'),
      const StyledLine('Tik tak.'),
    ]);
    final cat = s.lines.firstWhere((l) => l.speakers.contains('kot-latek'));
    expect(cat.text, 'Patrzcie!');
    expect(cat.directions, ['(z szafy wychodzi Stary Zegar)']);
    expect(s.characters[1].aliases, isEmpty);
    expect(s.lines.last.speakers, ['stary-zegar']);
  });

  test('an unterminated /cue is a direction to the end of the block', () {
    final s = _build([
      ...cast,
      const StyledLine('/ Kot przesuwa szafę,'),
      const StyledLine('Zegar patrzy.'),
      const StyledLine('Kot Łatek'),
      const StyledLine('Uff.'),
    ]);
    expect(s.lines[1].kind, LineKind.direction);
    expect(s.lines[1].directions.single, startsWith('/ Kot przesuwa'));
  });
}
