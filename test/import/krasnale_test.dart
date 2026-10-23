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
    ]);
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
      final intro = s.lines[song.start - 1];
      expect(intro.kind, LineKind.direction, reason: song.id);
      expect(intro.directions.single, contains('śpiew'), reason: song.id);
      expect(song.title.length, lessThanOrEqualTo(42));
    }

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
