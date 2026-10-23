import 'dart:typed_data';

import 'package:sufler/import/pdf/pdf_file.dart';
import 'package:sufler/import/pdf/pdf_lexer.dart';

/// One decoded character code: its Unicode text and advance (1/1000 em).
typedef Glyph = ({int code, String text, double width, bool isSpace});

/// The parts of a font needed to read text: code -> Unicode, and widths.
class PdfFont {
  /// Reads the font dictionary [d] from [file].
  PdfFont(PdfFile file, PdfDict d) {
    final subtype = nameOf(d['Subtype']);
    _composite = subtype == 'Type0';
    final toUnicode = file.resolve(d['ToUnicode']);
    if (toUnicode is PdfStream) _readCMap(file.decode(toUnicode));
    if (_composite) {
      final kids = file.resolve(d['DescendantFonts']);
      final cid = file.dict(kids is List && kids.isNotEmpty ? kids[0] : null);
      _readCidWidths(file, cid ?? const {});
    } else {
      _readSimpleWidths(file, d);
      _readEncoding(file, d['Encoding']);
    }
  }

  bool _composite = false;
  final List<(int len, int lo, int hi)> _ranges = [];
  final Map<int, String> _unicode = {};
  final Map<int, String> _encoding = {};
  final Map<int, double> _widths = {};
  double _defaultWidth = 500;

  /// Splits [bytes] into glyphs.
  List<Glyph> decode(Uint8List bytes) {
    final out = <Glyph>[];
    var i = 0;
    while (i < bytes.length) {
      final len = _codeLength(bytes, i);
      var code = 0;
      for (var k = 0; k < len && i + k < bytes.length; k++) {
        code = (code << 8) | bytes[i + k];
      }
      i += len;
      final text = _unicode[code] ?? _encoding[code] ?? _fallback(code);
      out.add((
        code: code,
        text: text,
        width: _widths[code] ?? _defaultWidth,
        isSpace: len == 1 && code == 32,
      ));
    }
    return out;
  }

  String _fallback(int code) =>
      _composite ? '' : (cp1252[code] ?? String.fromCharCode(code));

  int _codeLength(Uint8List b, int i) {
    for (final (len, lo, hi) in _ranges) {
      if (i + len > b.length) continue;
      var code = 0;
      for (var k = 0; k < len; k++) {
        code = (code << 8) | b[i + k];
      }
      if (code >= lo && code <= hi) return len;
    }
    return _composite ? 2 : 1;
  }

  void _readCMap(Uint8List data) {
    final lx = PdfLexer(data);
    final operands = <Object?>[];
    for (var t = lx.object(); t != PdfLexer.eof; t = lx.object()) {
      if (t is! PdfOp) {
        operands.add(t);
        continue;
      }
      switch (t.op) {
        case 'endcodespacerange':
          for (var k = 0; k + 1 < operands.length; k += 2) {
            final lo = operands[k];
            final hi = operands[k + 1];
            if (lo is PdfString && hi is PdfString) {
              _ranges.add((lo.bytes.length, _int(lo.bytes), _int(hi.bytes)));
            }
          }
        case 'endbfchar':
          for (var k = 0; k + 1 < operands.length; k += 2) {
            final src = operands[k];
            final dst = operands[k + 1];
            if (src is PdfString && dst is PdfString) {
              _unicode[_int(src.bytes)] = utf16be(dst.bytes);
            }
          }
        case 'endbfrange':
          for (var k = 0; k + 2 < operands.length; k += 3) {
            _bfRange(operands[k], operands[k + 1], operands[k + 2]);
          }
      }
      operands.clear();
    }
    _ranges.sort((a, b) => a.$1.compareTo(b.$1));
  }

  void _bfRange(Object? lo, Object? hi, Object? dst) {
    if (lo is! PdfString || hi is! PdfString) return;
    final a = _int(lo.bytes);
    final b = _int(hi.bytes);
    for (var c = a; c <= b && c - a < 0x10000; c++) {
      if (dst is List && c - a < dst.length) {
        final d = dst[c - a];
        if (d is PdfString) _unicode[c] = utf16be(d.bytes);
      } else if (dst is PdfString && dst.bytes.length >= 2) {
        final units = utf16beUnits(dst.bytes);
        units[units.length - 1] += c - a;
        _unicode[c] = String.fromCharCodes(units);
      }
    }
  }

  void _readSimpleWidths(PdfFile file, PdfDict d) {
    final first = file.resolve(d['FirstChar']);
    final widths = file.resolve(d['Widths']);
    if (first is! int || widths is! List) return;
    for (var k = 0; k < widths.length; k++) {
      final w = file.resolve(widths[k]);
      if (w is num) _widths[first + k] = w.toDouble();
    }
  }

  void _readCidWidths(PdfFile file, PdfDict cid) {
    final dw = file.resolve(cid['DW']);
    _defaultWidth = dw is num ? dw.toDouble() : 1000;
    final w = file.resolve(cid['W']);
    if (w is! List) return;
    var k = 0;
    while (k + 1 < w.length) {
      final start = file.resolve(w[k]);
      final next = file.resolve(w[k + 1]);
      if (start is! int) return;
      if (next is List) {
        for (var j = 0; j < next.length; j++) {
          final v = file.resolve(next[j]);
          if (v is num) _widths[start + j] = v.toDouble();
        }
        k += 2;
      } else if (next is int && k + 2 < w.length) {
        final v = file.resolve(w[k + 2]);
        for (var c = start; c <= next && c - start < 0x10000; c++) {
          if (v is num) _widths[c] = v.toDouble();
        }
        k += 3;
      } else {
        return;
      }
    }
  }

  void _readEncoding(PdfFile file, Object? enc) {
    final e = file.dict(enc);
    final diffs = e == null ? null : file.resolve(e['Differences']);
    if (diffs is! List) return;
    var code = 0;
    for (final item in diffs) {
      final x = file.resolve(item);
      if (x is int) {
        code = x;
      } else if (x is PdfName) {
        final u = glyphNameToUnicode(x.name);
        if (u != null) _encoding[code] = u;
        code++;
      }
    }
  }
}

int _int(Uint8List b) => b.fold(0, (v, x) => (v << 8) | x);

/// UTF-16BE code units of [b].
List<int> utf16beUnits(Uint8List b) => [
  for (var i = 0; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1],
];

/// Decodes UTF-16BE (a ToUnicode destination).
String utf16be(Uint8List b) => b.length == 1
    ? String.fromCharCode(b[0])
    : String.fromCharCodes(utf16beUnits(b));

/// Windows-1252 codes that differ from Latin-1.
const cp1252 = <int, String>{
  0x80: '€', 0x85: '…', 0x91: '‘', 0x92: '’', 0x93: '“', 0x94: '”', //
  0x95: '•', 0x96: '–', 0x97: '—', 0x8a: 'Š', 0x8c: 'Œ', 0x9a: 'š',
};

/// Unicode for a glyph name: `uniXXXX`, single letters, Polish letters.
String? glyphNameToUnicode(String name) {
  final uni = RegExp(r'^uni([0-9A-Fa-f]{4})$').firstMatch(name);
  if (uni != null) return String.fromCharCode(int.parse(uni[1]!, radix: 16));
  if (name.length == 1) return name;
  const named = {
    'space': ' ', 'period': '.', 'comma': ',', 'hyphen': '-', //
    'aogonek': 'ą', 'Aogonek': 'Ą', 'cacute': 'ć', 'Cacute': 'Ć',
    'eogonek': 'ę', 'Eogonek': 'Ę', 'lslash': 'ł', 'Lslash': 'Ł',
    'nacute': 'ń', 'Nacute': 'Ń', 'oacute': 'ó', 'Oacute': 'Ó',
    'sacute': 'ś', 'Sacute': 'Ś', 'zacute': 'ź', 'Zacute': 'Ź',
    'zdotaccent': 'ż', 'Zdotaccent': 'Ż', 'quotedbl': '"', 'bullet': '•',
    'parenleft': '(', 'parenright': ')', 'slash': '/', 'colon': ':',
    'exclam': '!', 'question': '?', 'ellipsis': '…', 'endash': '–',
  };
  return named[name];
}
