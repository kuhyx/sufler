import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/import_document.dart';
import 'package:sufler/import/pdf/pdf_reader.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:sufler/model/script.dart';

// test/fixtures/synthetic_play.pdf is rendered from synthetic_play.fodt
// (written for these tests) with LibreOffice:
//   soffice --headless --convert-to pdf test/fixtures/synthetic_play.fodt
const _fixture = 'test/fixtures/synthetic_play.pdf';

void main() {
  final bytes = File(_fixture).readAsBytesSync();

  test('extracts text in reading order with Polish letters', () {
    final lines = readPdf(bytes).where((l) => l.text.trim().isNotEmpty);
    final texts = lines.map((l) => l.text.trim()).toList();
    expect(texts.first, 'Jan Testowy');
    expect(texts, contains(matches(r'^•\s+Kot Łatek \(Bajka o kocie\)$')));
    expect(texts, contains('To tylko ja, mała myszka.'));
    expect(texts.last, 'Północ.');
    expect(texts.length, 27);
  });

  test('recovers fill colours', () {
    final lines = readPdf(bytes);
    Tint tint(String text) =>
        lines.firstWhere((l) => l.text.trim() == text).tint;
    expect(tint('Tik tak, tik tak, mija noc'), Tint.song);
    expect(tint('Gwiazdy świecą nad dachem'), Tint.recitation);
    expect(tint('Scena pogrążona w ciszy'), Tint.recitation);
    expect(tint('To tylko ja, mała myszka.'), Tint.normal);
    expect(tint('Stary Zegar'), Tint.normal);
  });

  test('importDocument builds the script from the PDF', () async {
    final s = await importDocument(fileName: 'Zegar.PDF', bytes: bytes);
    expect(s.title, 'Zegar na strychu');
    expect(s.source, 'Zegar.PDF');
    expect(s.id, hasLength(64));
    expect(s.scenes.map((x) => x.title), ['Scena 1', 'Scena 4']);
    expect(s.songs.single.title, 'Piosenka Zegara');
    final lyrics = s.lines.where((l) => l.kind == LineKind.song);
    expect(lyrics.map((l) => l.speakers.single).toSet(), {'stary-zegar'});
    expect(s.lines.where((l) => l.kind == LineKind.recitation).length, 2);
    expect(s.characters.first.aliases, ['Stray Zegar']);
  });
}
