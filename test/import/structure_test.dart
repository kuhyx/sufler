import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/structure/build_script.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/script.dart';

const _n = Tint.normal;
const _r = Tint.song;
const _b = Tint.recitation;

Script _build(List<(Tint, String)> lines) => buildScript(
  [for (final (t, s) in lines) StyledLine(s, tint: t)],
  id: 'x',
  source: 'synthetic.odt',
);

/// A synthetic play exercising every structuring rule.
final _play = <(Tint, String)>[
  (_n, 'Jan Testowy'),
  (_n, '"Zegar na strychu"'),
  (_n, 'Bohaterowie:'),
  (_n, '1. Strych:'),
  (_n, '•    Stary Zegar (Opowieść o czasie)'),
  (_n, '•    Myszka Ćma (Opowieść o czasie)'),
  (_n, '•    Kot Łatek (Bajka o kocie)'),
  (_n, '•    Sowa i Nietoperz (Bajka nocna)'),
  (_r, 'Legenda: czerwone wersy się śpiewa'),
  (_n, 'Scena 1'),
  (_n, '/Ciemność/'),
  (_n, 'Stary Zegar'),
  (_n, 'Tik tak, kto chodzi po strychu? (ziewa) Pokaż się!'),
  (_n, 'Myszka'),
  (_n, 'To tylko ja.'),
  (_n, 'Stray Zegar'),
  (_n, 'Myszko, nie bój się /.../ ja nie'),
  (_n, 'gryzę (uśmiecha'),
  (_n, 'się szeroko)'),
  (_n, 'Piosenka Zegara'),
  (_r, 'Tik tak, tik tak, mija noc'),
  (_r, 'Wskazówki kręcą się w krąg (bije)'),
  (_n, 'Kot Łatek, Myszka Ćma'),
  (_n, 'Brawo!'),
  (_n, '(Kot wskakuje na skrzynię)'),
  (_n, 'Scena 4'),
  (_n, '(Noc. Księżyc'),
  (_n, 'świeci.)'),
  (_n, 'Kot Łatek'),
  (_n, 'Myszko, czy wiesz która godzina?'),
  (_b, 'Gwiazdy świecą nad dachem'),
  (_b, 'Scena pogrążona w ciszy'),
  (_n, 'Myszka Ćma'),
  (_n, 'Myszko, mówisz do siebie.'),
  (_n, 'Scena 4'),
  (_n, '"Piosenka Nocy"'),
  (_n, 'Cicho, cicho, noc nadchodzi'),
  (_n, 'Gwiazdy patrzą z góry'),
  (_n, 'Sowa'),
  (_n, 'Uhu. Była kiedyś taka piosenka o nocy.'),
  (_r, 'Sowa i Nietoperz śpiewają piosenkę'),
  (_r, 'Lecimy w ciemność'),
  (_n, 'Stary Zegar'),
  (_n, 'Północ.'),
];

void main() {
  late Script s;
  setUp(() => s = _build(_play));
  List<ScriptLine> said(String id) =>
      s.lines.where((l) => l.speakers.contains(id)).toList();

  test('title is the quoted line, cast list drops source tales', () {
    expect(s.title, 'Zegar na strychu');
    expect(s.characters.map((c) => c.id), [
      'stary-zegar',
      'myszka-cma',
      'kot-latek',
      'sowa',
      'nietoperz',
    ]);
  });

  test('typo and prefix headings fold into aliases', () {
    final zegar = s.characters.firstWhere((c) => c.id == 'stary-zegar');
    expect(zegar.aliases, ['Stray Zegar']);
    expect(s.characters[1].aliases, ['Myszka']);
    expect(said('stary-zegar').where((l) => l.kind == LineKind.dialogue), [
      hasText('Tik tak, kto chodzi po strychu? Pokaż się!'),
      hasText('Myszko, nie bój się ja nie\ngryzę'),
      hasText('Północ.'),
    ]);
  });

  test('directions are removed from text and kept', () {
    final first = said('stary-zegar').first;
    expect(first.directions, ['(ziewa)']);
    final second = said('stary-zegar')[1];
    expect(second.directions, ['(uśmiecha się szeroko)']);
    expect(second.text, isNot(contains('/')));
    final cue = s.lines.firstWhere((l) => l.text.isEmpty);
    expect(cue.kind, LineKind.direction);
    expect(cue.directions, ['/Ciemność/']);
    final night = s.lines.firstWhere(
      (l) => l.directions.contains('(Noc. Księżyc świeci.)'),
    );
    expect(night.kind, LineKind.direction);
  });

  test('multi-speaker heading lists every id', () {
    final bravo = s.lines.firstWhere((l) => l.text == 'Brawo!');
    expect(bravo.speakers, ['kot-latek', 'myszka-cma']);
    expect(bravo.directions, ['(Kot wskakuje na skrzynię)']);
  });

  test('name-comma dialogue lines are not headings', () {
    expect(s.lines.map((l) => l.text), contains('Myszko, mówisz do siebie.'));
  });

  test('scenes keep their numbering, verse "Scena ..." is not one', () {
    expect(s.scenes.map((x) => x.title), ['Scena 1', 'Scena 4', 'Scena 4']);
    expect(s.scenes.map((x) => x.id), ['scena-1', 'scena-4', 'scena-4-2']);
    expect(s.scenes.last.end, s.lines.length - 1);
    expect(s.lines.first.kind, LineKind.heading);
  });

  test('song by colour: lyric lines inside the speaker block', () {
    final song = s.songs.first;
    expect(song.title, 'Piosenka Zegara');
    final lyrics = s.lines.where((l) => l.songId == song.id).toList();
    expect(lyrics.first.kind, LineKind.heading);
    expect(lyrics.skip(1).map((l) => l.text), [
      'Tik tak, tik tak, mija noc',
      'Wskazówki kręcą się w krąg',
    ]);
    expect(lyrics.skip(1).every((l) => l.kind == LineKind.song), isTrue);
    expect(lyrics[1].speakers, ['stary-zegar']);
    expect(lyrics[2].directions, ['(bije)']);
    expect(s.lines[song.end].text, 'Wskazówki kręcą się w krąg');
  });

  test('song by heading without colour runs to the next heading', () {
    expect(s.songs.map((x) => x.title), ['Piosenka Zegara', 'Piosenka Nocy']);
    final night = s.lines.where((l) => l.songId == 'piosenka-nocy').toList();
    expect(night.map((l) => l.kind), [
      LineKind.heading,
      LineKind.song,
      LineKind.song,
    ]);
    expect(night[1].speakers, isEmpty);
  });

  test('unheaded red run: intro is a direction, singers from it', () {
    final intro = s.lines.firstWhere(
      (l) => l.directions.contains('Sowa i Nietoperz śpiewają piosenkę'),
    );
    expect(intro.kind, LineKind.direction);
    final lyric = s.lines[intro.index + 1];
    expect(lyric.text, 'Lecimy w ciemność');
    expect(lyric.kind, LineKind.song);
    expect(lyric.speakers, ['sowa', 'nietoperz']);
  });

  test('blue text is recitation, one line per verse line', () {
    final verse = s.lines.where((l) => l.kind == LineKind.recitation);
    expect(verse.map((l) => l.text), [
      'Gwiazdy świecą nad dachem',
      'Scena pogrążona w ciszy',
    ]);
    expect(verse.first.speakers, ['kot-latek']);
  });

  test('preamble legend is not imported; indices are positions', () {
    expect(s.lines.map((l) => l.text), isNot(contains(startsWith('Legenda'))));
    for (var i = 0; i < s.lines.length; i++) {
      expect(s.lines[i].index, i);
    }
  });

  test('without a cast list, recurring capitalised headings are inferred', () {
    final t = _build([
      (_n, 'Sztuka'),
      (_n, 'Lis'),
      (_n, 'Dzień dobry.'),
      (_n, 'Wielki Wilk'),
      (_n, 'Jak to'),
      (_n, 'Lis'),
      (_n, 'Tak to.'),
      (_n, 'Wielki Wilk'),
      (_n, 'Jak to'),
      (_n, 'Wielki'),
      (_n, 'Do widzenia.'),
    ]);
    expect(t.characters.map((c) => c.name), ['Lis', 'Wielki Wilk']);
    expect(t.characters[1].aliases, ['Wielki']);
    expect(t.lines.map((l) => l.text), [
      'Dzień dobry.',
      'Jak to',
      'Tak to.',
      'Jak to',
      'Do widzenia.',
    ]);
  });
}

Matcher hasText(String text) =>
    isA<ScriptLine>().having((l) => l.text, 'text', text);
