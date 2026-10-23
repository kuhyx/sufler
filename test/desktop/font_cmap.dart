/// Reads which code points a TrueType font maps (its `cmap` table), so a
/// test can tell whether a bundled font covers a glyph the UI shows.
library;

import 'dart:io';
import 'dart:typed_data';

/// Every BMP code point the font at [path] maps to a real glyph (Windows
/// Unicode BMP subtable, format 4).
Set<int> bmpCoverage(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  final tables = b.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final rec = 12 + 16 * i;
    if (String.fromCharCodes(Uint8List.sublistView(b, rec, rec + 4)) ==
        'cmap') {
      cmap = b.getUint32(rec + 8);
    }
  }
  if (cmap < 0) throw FormatException('no cmap in $path');
  for (var i = 0; i < b.getUint16(cmap + 2); i++) {
    final rec = cmap + 4 + 8 * i;
    final sub = cmap + b.getUint32(rec + 4);
    final windowsBmp = b.getUint16(rec) == 3 && b.getUint16(rec + 2) == 1;
    if (windowsBmp && b.getUint16(sub) == 4) return _format4(b, sub);
  }
  throw FormatException('no format-4 Windows BMP cmap in $path');
}

Set<int> _format4(ByteData b, int sub) {
  final segs = b.getUint16(sub + 6) ~/ 2;
  final ends = sub + 14;
  final starts = ends + 2 * segs + 2;
  final deltas = starts + 2 * segs;
  final offsets = deltas + 2 * segs;
  final out = <int>{};
  for (var s = 0; s < segs; s++) {
    final start = b.getUint16(starts + 2 * s);
    final end = b.getUint16(ends + 2 * s);
    final delta = b.getUint16(deltas + 2 * s);
    final offset = b.getUint16(offsets + 2 * s);
    for (var c = start; c <= end && c != 0xFFFF; c++) {
      var glyph = 0;
      if (offset == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        final at = offsets + 2 * s + offset + 2 * (c - start);
        final raw = b.getUint16(at);
        glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF;
      }
      if (glyph != 0) out.add(c);
    }
  }
  return out;
}
