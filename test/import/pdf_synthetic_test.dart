// A PDF assembled in memory (no dart:io), so this also runs on the web:
// flutter test --platform chrome test/import/pdf_synthetic_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/pdf/pdf_reader.dart';
import 'package:sufler/import/styled_line.dart';

/// Builds a one-page PDF: [content] is the page stream (Flate-compressed),
/// F1 is a Type0 font with 2-byte codes and a ToUnicode CMap.
Uint8List _pdf(String content) {
  const cmap = '''
/CIDInit /ProcSet findresource begin 12 dict begin begincmap
1 begincodespacerange <0000> <FFFF> endcodespacerange
2 beginbfchar <0001> <0141> <0002> <0105> endbfchar
1 beginbfrange <0010> <0012> <0061> endbfrange
1 beginbfrange <0020> <0021> [<017B> <0020>] endbfrange
endcmap CMapName currentdict /CMap defineresource pop end end''';
  final page = const ZLibEncoder().encode(latin1.encode(content));
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    'STREAM4',
    '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /Identity-H '
        '/DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
    '<< /Type /Font /Subtype /CIDFontType2 /DW 600 /W [1 [500 500]] >>',
    '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
  ];
  final out = BytesBuilder()..add(latin1.encode('%PDF-1.7\n'));
  for (final (i, body) in objects.indexed) {
    out.add(latin1.encode('${i + 1} 0 obj\n'));
    if (body == 'STREAM4') {
      out
        ..add(
          latin1.encode('<< /Length ${page.length} /Filter /FlateDecode >>'),
        )
        ..add(latin1.encode('\nstream\n'))
        ..add(page)
        ..add(latin1.encode('\nendstream'));
    } else {
      out.add(latin1.encode(body));
    }
    out.add(latin1.encode('\nendobj\n'));
  }
  out.add(latin1.encode('trailer << /Root 1 0 R >>\n%%EOF\n'));
  return out.takeBytes();
}

void main() {
  test('Type0 font, ToUnicode ranges, colours, TJ and line order', () {
    final lines = readPdf(
      _pdf('''
q 1 0 0 1 0 0 cm
BT /F1 12 Tf 0.79 0.13 0.12 rg 1 0 0 1 72 700 Tm <00010002> Tj ET
BT /F1 12 Tf 0 g 72 720 Td [<0020> -300 <00210010> 50 <00110012>] TJ ET
BT /F1 12 Tf /DeviceRGB cs 0.16 0.38 0.6 sc 72 680 Td <00100011> Tj
0 0 0 1 k 50 0 Td <0012> Tj ET
Q
'''),
    );
    expect(lines.map((l) => l.text), ['Ż abc', 'Łą', 'ab c']);
    expect(lines.map((l) => l.tint), [Tint.normal, Tint.song, Tint.recitation]);
  });

  test('non-PDF bytes are rejected', () {
    expect(() => readPdf(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
