// Red (sung) passages with no "Piosenka …" heading still become songs, so
// an actor can pick them as a song role.
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

const _n = Tint.normal;
const _r = Tint.song;
const _b = Tint.recitation;

const _long = 'Hej ho, hej ho, do roboty by się szło, a potem spać';

final _play = <(Tint, String)>[
  (_n, 'Bohaterowie:'),
  (_n, '- Sowa'),
  (_n, '- Nietoperz'),
  (_n, 'Scena 1'),
  (_n, 'Sowa'),
  (_n, 'Posłuchaj.'),
  (_r, '(wstaje)'),
  (_r, _long),
  (_r, 'Druga zwrotka (klaszcze)'),
  (_n, '(Cisza)'),
  (_r, 'Sowa i Nietoperz śpiewają piosenkę'),
  (_r, 'Lecimy w ciemność'),
  (_r, 'Lecimy w noc'),
  (_b, 'Wiersz o gwiazdach'),
  (_n, 'Nietoperz'),
  (_n, 'Koniec.'),
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
  List<ScriptLine> sung(Section song) =>
      s.lines.where((l) => l.songId == song.id).toList();

  test('each red run without a heading is its own song section', () {
    expect(s.songs.map((x) => x.title), [
      '♪ ${_long.substring(0, 39).trimRight()}…',
      '♪ Lecimy w ciemność',
    ]);
    expect(s.songs.map((x) => x.id), [
      'hej-ho-hej-ho-do-roboty-by-sie-szlo',
      'lecimy-w-ciemnosc',
    ]);
    expect(s.songs.first.title.length, lessThanOrEqualTo(42));
  });

  test('the section spans exactly the lyric lines, all tagged', () {
    for (final song in s.songs) {
      final lines = s.lines.sublist(song.start, song.end + 1);
      expect(lines.every((l) => l.songId == song.id), isTrue);
      expect(sung(song), lines);
      expect(s.lines[song.start].kind, LineKind.song);
      expect(s.lines[song.end].kind, LineKind.song);
    }
    final [first, second] = s.songs;
    expect(sung(first).map((l) => l.text), [_long, 'Druga zwrotka']);
    expect(sung(first).last.directions, ['(klaszcze)']);
    expect(sung(second).map((l) => l.text), [
      'Lecimy w ciemność',
      'Lecimy w noc',
    ]);
  });

  test('intros and leading red directions stay outside the section', () {
    final lead = s.lines.firstWhere((l) => l.directions.contains('(wstaje)'));
    expect(lead.kind, LineKind.direction);
    expect(lead.songId, isNull);
    final intro = s.lines.firstWhere(
      (l) => l.directions.contains('Sowa i Nietoperz śpiewają piosenkę'),
    );
    expect(intro.kind, LineKind.direction);
    expect(intro.songId, isNull);
  });

  test('singers: the speaker block, or those named in the intro', () {
    final [first, second] = s.songs;
    expect(sung(first).first.speakers, ['sowa']);
    expect(sung(second).first.speakers, ['sowa', 'nietoperz']);
  });

  test('picking the song role owns its lyrics and nothing else', () {
    final role = Role.song(s.songs.last.id);
    final mine = s.lines.where((l) => isMine(l, {role})).map((l) => l.text);
    expect(mine, ['Lecimy w ciemność', 'Lecimy w noc']);
  });

  test('blue verse after a red run is still recitation, not a song', () {
    final verse = s.lines.firstWhere((l) => l.text == 'Wiersz o gwiazdach');
    expect(verse.kind, LineKind.recitation);
    expect(verse.songId, isNull);
  });
}
