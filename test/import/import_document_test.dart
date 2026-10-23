import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sufler/import/google_doc.dart';
import 'package:sufler/import/import_document.dart';

const _txt = 'Sztuka\nLis\nDzień dobry.\nWilk\nCześć.\nLis\nPa.\nWilk\nPa!\n';

Uint8List _docx() {
  const w =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  String p(String t) => '<w:p><w:r><w:t>$t</w:t></w:r></w:p>';
  final body = [for (final l in _txt.trim().split('\n')) p(l)].join();
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(
        'word/document.xml',
        utf8.encode('<w:document $w><w:body>$body</w:body></w:document>'),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('txt import: id is sha256 of the bytes', () async {
    final bytes = Uint8List.fromList(utf8.encode(_txt));
    final s = await importDocument(fileName: 'sztuka.txt', bytes: bytes);
    expect(s.id, sha256Hex(bytes));
    expect(s.id, hasLength(64));
    expect(s.title, 'Sztuka');
    expect(s.characters.map((c) => c.id), ['lis', 'wilk']);
    expect(s.lines.map((l) => l.text), [
      'Dzień dobry.',
      'Cześć.',
      'Pa.',
      'Pa!',
    ]);
  });

  test('unknown extension is a FormatException', () {
    expect(
      () => importDocument(fileName: 'a.rtf', bytes: Uint8List(0)),
      throwsFormatException,
    );
  });

  test('google doc id is parsed from share links', () {
    expect(
      googleDocId(
        'https://docs.google.com/document/d/1AbC_d-9/edit?usp=sharing',
      ),
      '1AbC_d-9',
    );
    expect(googleDocId('docs.google.com/document/u/0/d/XyZ/view'), 'XyZ');
    expect(() => googleDocId('https://example.com/d/1'), throwsFormatException);
  });

  test('google doc downloads the docx export', () async {
    late Uri asked;
    final client = MockClient((req) async {
      asked = req.url;
      return http.Response.bytes(_docx(), 200);
    });
    final s = await importGoogleDoc(
      'https://docs.google.com/document/d/DOC1/edit',
      client: client,
    );
    expect(asked.toString(), contains('DOC1'));
    expect(s.source, 'https://docs.google.com/document/d/DOC1/edit');
    expect(s.characters.map((c) => c.name), ['Lis', 'Wilk']);
  });

  test('private google doc gives a clear error', () async {
    final client = MockClient(
      (_) async => http.Response('<html>Sign in</html>', 200),
    );
    expect(
      importGoogleDoc(
        'https://docs.google.com/document/d/P/edit',
        client: client,
      ),
      throwsA(
        isA<GoogleDocException>().having(
          (e) => e.message,
          'message',
          contains('anyone with the link'),
        ),
      ),
    );
  });
}
