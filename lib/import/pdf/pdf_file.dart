import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sufler/import/pdf/pdf_lexer.dart';

/// A stream object: its dictionary and still-encoded bytes.
class PdfStream {
  /// Creates a stream.
  PdfStream(this.dict, this.raw);

  /// Stream dictionary.
  final PdfDict dict;

  /// Encoded data.
  final Uint8List raw;
}

final _objHeader = RegExp(r'(\d+)\s+(\d+)\s+obj\b');

/// Random access to the objects of a PDF.
///
/// Objects are indexed by scanning for `n g obj` headers rather than by
/// trusting the xref table, which tolerates broken offsets and incremental
/// updates (the last definition wins). Object streams are unpacked too.
class PdfFile {
  /// Indexes [bytes].
  PdfFile(this.bytes) {
    _scan();
  }

  /// The whole file.
  final Uint8List bytes;
  final Map<int, Object?> _objects = {};

  void _scan() {
    final text = latin1.decode(bytes);
    var pos = 0;
    final objStreams = <PdfStream>[];
    while (true) {
      final m = _objHeader.allMatches(text, pos).firstOrNull;
      if (m == null) break;
      final lexer = PdfLexer(bytes, m.end);
      var value = lexer.object();
      pos = lexer.pos;
      final next = lexer.token();
      if (value is PdfDict && next is PdfOp && next.op == 'stream') {
        final (stream, end) = _stream(text, value, lexer.pos);
        value = stream;
        pos = end;
        if (_name(stream.dict['Type']) == 'ObjStm') objStreams.add(stream);
      }
      _objects[int.parse(m[1]!)] = value;
    }
    objStreams.forEach(_unpack);
  }

  (PdfStream, int) _stream(String text, PdfDict dict, int at) {
    var start = at;
    if (start < bytes.length && bytes[start] == 0x0d) start++;
    if (start < bytes.length && bytes[start] == 0x0a) start++;
    final length = dict['Length'];
    var end = -1;
    if (length is int &&
        start + length <= bytes.length &&
        text.startsWith('endstream', _skipWhite(start + length))) {
      end = start + length;
    } else {
      end = text.indexOf('endstream', start);
      if (end < 0) end = bytes.length;
    }
    var dataEnd = end;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0a) dataEnd--;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0d) dataEnd--;
    final data = Uint8List.sublistView(bytes, start, dataEnd);
    return (PdfStream(dict, data), end);
  }

  int _skipWhite(int i) {
    var p = i;
    while (p < bytes.length && (bytes[p] <= 0x20)) {
      p++;
    }
    return p;
  }

  void _unpack(PdfStream s) {
    final data = decode(s);
    final n = s.dict['N'];
    final first = s.dict['First'];
    if (n is! int || first is! int) return;
    final header = PdfLexer(data);
    for (var i = 0; i < n; i++) {
      final num = header.token();
      final off = header.token();
      if (num is! int || off is! int) return;
      if (_objects.containsKey(num)) continue;
      _objects[num] = PdfLexer(data, first + off).object();
    }
  }

  /// Follows references until a direct object.
  Object? resolve(Object? o) {
    var x = o;
    for (var i = 0; i < 32 && x is PdfRef; i++) {
      x = _objects[x.num];
    }
    return x is PdfRef ? null : x;
  }

  /// Resolves [o] as a dictionary (a stream yields its dictionary).
  PdfDict? dict(Object? o) {
    final x = resolve(o);
    if (x is PdfStream) return x.dict;
    return x is PdfDict ? x : null;
  }

  /// Every object, for catalog lookup.
  Iterable<Object?> get objects => _objects.values;

  /// Decoded stream data; unsupported filters yield empty bytes.
  Uint8List decode(PdfStream s) {
    final f = resolve(s.dict['Filter']);
    final filters = f is List ? f.map(resolve).toList() : [?f];
    var data = s.raw;
    for (final filter in filters) {
      final name = _name(filter);
      if (name == 'FlateDecode' || name == 'Fl') {
        data = _inflate(data);
      } else {
        return Uint8List(0);
      }
    }
    return data;
  }

  static Uint8List _inflate(Uint8List data) {
    try {
      return Uint8List.fromList(const ZLibDecoder().decodeBytes(data));
    } on Object {
      try {
        return Uint8List.fromList(Inflate(data.sublist(2)).getBytes());
      } on Object {
        return Uint8List(0);
      }
    }
  }

  /// The pages in reading order, each with its inherited resources.
  List<(PdfDict page, PdfDict resources)> pages() {
    final catalog = objects.whereType<PdfDict>().lastWhere(
      (d) => _name(d['Type']) == 'Catalog',
      orElse: () => const {},
    );
    final out = <(PdfDict, PdfDict)>[];
    void walk(Object? node, PdfDict? res, int depth) {
      final d = dict(node);
      if (d == null || depth > 64) return;
      final r = dict(d['Resources']) ?? res ?? const {};
      final kids = resolve(d['Kids']);
      if (kids is List) {
        for (final k in kids) {
          walk(k, r, depth + 1);
        }
      } else if (_name(d['Type']) != 'Pages') {
        out.add((d, r));
      }
    }

    walk(catalog['Pages'], null, 0);
    return out;
  }
}

String? _name(Object? o) => o is PdfName ? o.name : null;

/// The name string of [o], or null when it is not a [PdfName].
String? nameOf(Object? o) => _name(o);
