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
  ];

  test('a standalone "Finał" ends the speech and starts a scene', () {
    final s = _build([
      ...cast,
      const StyledLine('Scena 2'),
      const StyledLine('Kot Łatek'),
      const StyledLine('Uciekajmy! (wybiega)'),
      const StyledLine('Finał'),
      const StyledLine('"Piosenka Kota Łatka"'),
      const StyledLine('Miau miau', tint: Tint.song),
    ]);
    final speech = s.lines.singleWhere((l) => l.kind == LineKind.dialogue);
    expect(speech.text, 'Uciekajmy!');
    expect(speech.speakers, ['kot-latek']);
    final finale = s.lines[speech.index + 1];
    expect(finale.kind, LineKind.heading);
    expect(finale.text, 'Finał');
    expect(finale.isSpoken, isFalse);
    expect(s.scenes.map((x) => (x.id, x.title, x.start, x.end)), [
      ('scena-2', 'Scena 2', 0, speech.index),
      ('final', 'Finał', finale.index, s.lines.length - 1),
    ]);
    expect(s.lines.last.sceneId, 'final');
    expect(s.lines.last.speakers, ['kot-latek']);
  });

  test('Prolog and Epilog start scenes; numbering stays as written', () {
    final s = _build([
      ...cast,
      const StyledLine('PROLOG'),
      const StyledLine('Stary Zegar'),
      const StyledLine('Tik tak.'),
      const StyledLine('Scena 3'),
      const StyledLine('Kot Łatek'),
      const StyledLine('Miau.'),
      const StyledLine('Epilog:'),
      const StyledLine('Stary Zegar'),
      const StyledLine('Północ.'),
      const StyledLine('Finał.'),
    ]);
    expect(s.scenes.map((x) => x.title), [
      'PROLOG',
      'Scena 3',
      'Epilog',
      'Finał',
    ]);
    expect(s.lines.first.kind, LineKind.heading);
    expect(s.lines.where((l) => l.isSpoken), hasLength(3));
  });

  test('Wstęp, Akt <n>, Antrakt are headings inside the current scene', () {
    final s = _build([
      ...cast,
      const StyledLine('Scena 1'),
      const StyledLine('Kot Łatek'),
      const StyledLine('Miau.'),
      const StyledLine('Antrakt'),
      const StyledLine('Akt 2'),
      const StyledLine('Akt II'),
      const StyledLine('Wstęp'),
      const StyledLine('Stary Zegar'),
      const StyledLine('Tik tak.'),
    ]);
    final heads = s.lines.where((l) => l.kind == LineKind.heading);
    expect(heads.map((l) => l.text), [
      'Scena 1',
      'Antrakt',
      'Akt 2',
      'Akt II',
      'Wstęp',
    ]);
    expect(heads.every((l) => l.sceneId == 'scena-1'), isTrue);
    expect(s.scenes.map((x) => x.title), ['Scena 1']);
    final spoken = s.lines.where((l) => l.isSpoken).map((l) => l.text);
    expect(spoken, ['Miau.', 'Tik tak.']);
  });

  test('the words inside a sentence or a longer line stay text', () {
    final s = _build([
      ...cast,
      const StyledLine('Wstęp - zapowiedź reżysera'),
      const StyledLine('Scena 1'),
      const StyledLine('Kot Łatek'),
      const StyledLine('Finał!'),
      const StyledLine('Akt odwagi'),
      const StyledLine('Finał jest blisko'),
    ]);
    expect(s.scenes.map((x) => x.title), ['Scena 1']);
    final speech = s.lines.singleWhere((l) => l.kind == LineKind.dialogue);
    expect(speech.text, 'Finał!\nAkt odwagi\nFinał jest blisko');
  });
}
