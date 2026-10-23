// Integration test against the real (copyrighted, never committed) script.
// Run with: SUFLER_SCRIPT_PDF=/path/to/krasnale.pdf flutter test \
//   test/import/krasnale_test.dart
// Counts below were verified by hand against `pdftotext -layout` (songs:
// `pdftohtml -xml -i -stdout` font colours).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/import_document.dart';
import 'package:sufler/model/script.dart';

final _path = Platform.environment['SUFLER_SCRIPT_PDF'];

void main() {
  late Script s;
  setUpAll(() async {
    final path = _path;
    if (path == null) return;
    final file = File(path);
    s = await importDocument(
      fileName: file.uri.pathSegments.last,
      bytes: file.readAsBytesSync(),
    );
  });

  test('Krasnale (się) rządzą imports with the hand-counted structure', () {
    expect(s.title, 'Krasnale (się) rządzą');
    expect(s.scenes.map((x) => x.title), [
      'Scena 1',
      'Scena 3',
      'Scena 3',
      'Scena 5',
      'Scena 6',
      'Scena 7',
      'Scena 8',
      'Scena 9',
      'Finał',
    ]);
    // "Finał" stands alone between "/światło/" and "Piosenka Krasnali 2"
    // (`pdftotext -layout`): a scene heading, not the end of Żagiewka's line.
    final finale = s.scenes.last;
    expect(s.lines[finale.start].kind, LineKind.heading);
    expect(s.lines[finale.start - 1].speakers, ['zagiewka']);
    expect(s.lines.where((l) => l.text.contains('Finał')), hasLength(1));
    expect(s.songs.last.start, finale.start + 1);
    expect(finale.end, s.lines.length - 1);
    // 11 "Piosenka …" headings + 2 red runs with no heading, each opened by
    // a red "… śpiewa(ją) piosenkę" line (counted from the red fontspecs of
    // `pdftohtml -xml -i -stdout`: 14 red runs = legend + 11 + 2).
    final headed = s.songs.where((x) => !x.title.startsWith('♪ ')).toList();
    final unheaded = s.songs.where((x) => x.title.startsWith('♪ ')).toList();
    expect(headed, hasLength(11));
    expect(unheaded, hasLength(2));
    expect(headed.first.title, 'Piosenka Krasnali');
    expect(headed.last.title, 'Piosenka Krasnali 2');
    for (final song in unheaded) {
      // The intro, then possibly a leading singer tag ("R."): unspoken
      // directions outside the section.
      final before = s.lines.sublist(0, song.start).reversed;
      final lead = before.takeWhile((l) => l.kind == LineKind.direction);
      expect(
        lead.any((l) => l.directions.any((d) => d.contains('śpiew'))),
        isTrue,
        reason: song.id,
      );
      expect(song.title.length, lessThanOrEqualTo(42));
    }
    // The duet's 3 singer tags are unspoken directions, not dropped.
    // ... and so is the "Finał" heading.
    expect(s.lines, hasLength(864));
    expect(s.lines.where((l) => l.isSpoken), hasLength(825));

    final ids = s.characters.map((c) => c.id).toSet();
    expect(
      ids,
      containsAll([
        'blystek',
        'koszalek-opalek',
        'podziomek',
        'pietrzyk',
        'zagiewka',
      ]),
    );
    final wolf = s.characters.firstWhere((c) => c.id == 'piaskowy-wilk');
    expect(wolf.aliases, contains('Piaksowy Wilk'));

    // 17 "Piaskowy Wilk" headings + 1 "Piaksowy Wilk" typo.
    final blocks = s.lines.where(
      (l) => l.kind == LineKind.dialogue && l.speakers.contains(wolf.id),
    );
    expect(blocks, hasLength(18));
    // Plus the 21 lyrics of "Piosenka Piaskowego Wilka".
    final sung = s.lines.where(
      (l) => l.kind == LineKind.song && l.speakers.contains(wolf.id),
    );
    expect(sung, hasLength(21));
    final said = blocks.map((l) => l.text).toSet();
    expect(said, containsAll(['Zawsze to samo...', 'Uwielbiam łamigłówki']));
    // Directions removed, PDF soft wraps joined with a space.
    expect(
      said,
      contains(
        'Piaskowe Wilki nie jedzą Krasnali! Piaskowe Wilki nie jedzą ludzi.',
      ),
    );
  }, skip: _path == null ? 'set SUFLER_SCRIPT_PDF to run' : false);

  test('Żagiewka: one dialogue line per heading, plus group songs', () {
    // 86 standalone "Żagiewka" headings (cast-list bullet excluded); no
    // multi-speaker heading names her. The closing "Koniec;)" after the
    // finale is not hers.
    final blocks = s.lines.where(
      (l) => l.kind == LineKind.dialogue && l.speakers.contains('zagiewka'),
    );
    expect(blocks, hasLength(86));
    expect(blocks.where((l) => l.speakers.length > 1), isEmpty);
    // Sung: all 24 + 20 lyrics of both "Piosenka Krasnali" (she is in the
    // cast-list group "1. Krasnale"), plus 6 more; 86 + 50 = 136 lines.
    for (final song in s.songs.where((x) => x.title.contains('Krasnali'))) {
      final lyrics = s.lines.where((l) => l.songId == song.id && l.isSpoken);
      expect(lyrics.map((l) => l.speakers.length).toSet(), {5});
      expect(lyrics.every((l) => l.speakers.contains('zagiewka')), isTrue);
    }
    final sung = s.lines.where(
      (l) => l.kind == LineKind.song && l.speakers.contains('zagiewka'),
    );
    expect(sung, hasLength(50));
    final hers = s.lines.where(
      (l) => l.isSpoken && l.speakers.contains('zagiewka'),
    );
    expect(hers, hasLength(136));
    expect(blocks.map((l) => l.text), contains('Achh ci celebryci....'));
    expect(s.lines.last.isSpoken, isFalse);
  }, skip: _path == null ? 'set SUFLER_SCRIPT_PDF to run' : false);

  test('the Róża / Lis duet follows its R. / L. / Razem tags', () {
    // Scena 3 (pdftotext -layout): "R." 4 lyric lines, "L." 4, "Razem" 1.
    final duet = s.songs.singleWhere(
      (x) => s.lines[x.start - 1].directions.contains('R.'),
    );
    final lyrics = s.lines
        .sublist(duet.start, duet.end + 1)
        .where((l) => l.isSpoken)
        .map((l) => l.speakers.join('+'));
    expect(lyrics, [
      ...List.filled(4, 'roza'),
      ...List.filled(4, 'lis'),
      'roza+lis',
    ]);
    final tags = s.lines
        .sublist(duet.start - 1, duet.end + 1)
        .where((l) => l.kind == LineKind.direction);
    expect(tags.map((l) => l.directions.single), ['R.', 'L.', 'Razem']);
    expect(s.songs.where((x) => x.title.length <= 5), isEmpty);
  }, skip: _path == null ? 'set SUFLER_SCRIPT_PDF to run' : false);

  test('songs are delimited by colour', () {
    // Every song ends on a red lyric line, not on the next black line.
    // A headed song starts on its heading, an unheaded one on its first lyric.
    for (final song in s.songs) {
      final last = s.lines[song.end];
      expect(last.kind, LineKind.song, reason: song.id);
      expect(
        s.lines[song.start].kind,
        song.title.startsWith('♪ ') ? LineKind.song : LineKind.heading,
        reason: song.id,
      );
    }
    final first = s.lines.where(
      (l) => l.songId == s.songs.first.id && l.kind == LineKind.song,
    );
    expect(first, hasLength(24));
    // The wolf's song sits inside his speech block.
    final wolfSong = s.songs.firstWhere(
      (x) => x.title == 'Piosenka Piaskowego Wilka',
    );
    expect(s.lines[wolfSong.end].speakers, ['piaskowy-wilk']);
    // Blue verse is recitation.
    expect(
      s.lines.where((l) => l.kind == LineKind.recitation).length,
      greaterThan(100),
    );
  }, skip: _path == null ? 'set SUFLER_SCRIPT_PDF to run' : false);
}
