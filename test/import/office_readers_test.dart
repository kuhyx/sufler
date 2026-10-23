import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/readers/docx_reader.dart';
import 'package:sufler/import/readers/odt_reader.dart';
import 'package:sufler/import/readers/txt_reader.dart';
import 'package:sufler/import/styled_line.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, body) {
    archive.add(ArchiveFile.bytes(name, utf8.encode(body)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _w =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

String _run(String text, [String? color]) =>
    '<w:r>${color == null ? '' : '<w:rPr><w:color w:val="$color"/></w:rPr>'}'
    '<w:t xml:space="preserve">$text</w:t></w:r>';

const _o =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"';

void main() {
  test('docx: paragraphs, w:br and run colours', () {
    final doc = _zip({
      'word/document.xml':
          '<w:document $_w><w:body>'
          '<w:p>${_run('Stary Zegar')}</w:p>'
          '<w:p>${_run('Tik ', '000000')}${_run('tak', 'auto')}</w:p>'
          '<w:p>${_run('Wskazówki', 'C9211E')}<w:r><w:br/></w:r>'
          '${_run('kręcą się', 'FF0000')}</w:p>'
          '<w:p>${_run('Gwiazdy świecą', '2A6099')}</w:p>'
          '<w:p/>'
          '</w:body></w:document>',
    });
    final lines = readDocx(doc);
    expect(lines.map((l) => l.text), [
      'Stary Zegar',
      'Tik tak',
      'Wskazówki',
      'kręcą się',
      'Gwiazdy świecą',
      '',
    ]);
    expect(lines.map((l) => l.tint), [
      Tint.normal,
      Tint.normal,
      Tint.song,
      Tint.song,
      Tint.recitation,
      Tint.normal,
    ]);
  });

  test('odt: automatic paragraph and span styles give the colour', () {
    final doc = _zip({
      'mimetype': 'application/vnd.oasis.opendocument.text',
      'content.xml':
          '<office:document-content $_o><office:automatic-styles>'
          '<style:style style:name="P1" style:family="paragraph">'
          '<style:text-properties fo:color="#c9211e"/></style:style>'
          '<style:style style:name="T1" style:family="text">'
          '<style:text-properties fo:color="#2a6099"/></style:style>'
          '</office:automatic-styles><office:body><office:text>'
          '<text:h>Scena 1</text:h>'
          '<text:p text:style-name="P1">Tik<text:s/>tak'
          '<text:line-break/>mija<text:tab/>noc</text:p>'
          '<text:p>Gwiazdy <text:span text:style-name="T1">świecą nad'
          ' dachem</text:span></text:p>'
          '<text:list><text:list-item><text:p>Lis</text:p>'
          '</text:list-item></text:list>'
          '</office:text></office:body></office:document-content>',
    });
    final lines = readOdt(doc);
    expect(lines.map((l) => l.text), [
      'Scena 1',
      'Tik tak',
      'mija\tnoc',
      'Gwiazdy świecą nad dachem',
      'Lis',
    ]);
    expect(lines.map((l) => l.tint), [
      Tint.normal,
      Tint.song,
      Tint.song,
      Tint.recitation,
      Tint.normal,
    ]);
  });

  test('txt: utf-8 lines, CRLF, BOM, no colour', () {
    final bytes = Uint8List.fromList([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('Żagiewka\r\nCześć!\n'),
    ]);
    final lines = readTxt(bytes);
    expect(lines.map((l) => l.text), ['Żagiewka', 'Cześć!', '']);
    expect(lines.every((l) => l.tint == Tint.normal), isTrue);
  });

  test('tintOf maps the script colours', () {
    expect(tintOf(0xc9211e), Tint.song);
    expect(tintOf(0xff0000), Tint.song);
    expect(tintOf(0xbf0041), Tint.song);
    expect(tintOf(0x2a6099), Tint.recitation);
    expect(tintOf(0x111111), Tint.normal);
    expect(tintOf(0x000000), Tint.normal);
    expect(tintOf(null), Tint.normal);
  });
}
