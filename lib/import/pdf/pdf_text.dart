import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sufler/import/pdf/pdf_file.dart';
import 'package:sufler/import/pdf/pdf_font.dart';
import 'package:sufler/import/pdf/pdf_lexer.dart';

/// A piece of text placed on the page, in device space (y grows upwards).
typedef TextChunk = ({
  String text,
  double x0,
  double x1,
  double y,
  double size,
  int? rgb,
});

typedef _M = List<double>;

_M _mul(_M a, _M b) => [
  a[0] * b[0] + a[1] * b[2],
  a[0] * b[1] + a[1] * b[3],
  a[2] * b[0] + a[3] * b[2],
  a[2] * b[1] + a[3] * b[3],
  a[4] * b[0] + a[5] * b[2] + b[4],
  a[4] * b[1] + a[5] * b[3] + b[5],
];

const _identity = <double>[1, 0, 0, 1, 0, 0];

int _rgb(double r, double g, double b) {
  int c(double v) => (v.clamp(0, 1) * 255).round();
  return (c(r) << 16) | (c(g) << 8) | c(b);
}

/// Runs a page's content streams and collects the text it shows, with the
/// fill colour in effect (rg/g/k/sc/scn) for each piece.
class PdfTextExtractor {
  /// Extracts from [file].
  new(this.file);

  /// The document.
  final PdfFile file;
  final Map<Object, PdfFont> _fonts = {};
  final List<TextChunk> _out = [];

  // Graphics state (q/Q stack) and text state.
  List<(_M, int?)> _stack = [];
  _M _ctm = _identity;
  int? _fill = 0;
  _M _tm = _identity;
  _M _tlm = _identity;
  PdfFont? _font;
  double _size = 12;
  double _tc = 0;
  double _tw = 0;
  double _th = 1;
  double _tl = 0;
  double _rise = 0;

  /// Text chunks of [page] in content order.
  List<TextChunk> page(PdfDict page, PdfDict resources) {
    _out.clear();
    _stack = [];
    _ctm = _identity;
    _fill = 0;
    final c = file.resolve(page['Contents']);
    final parts = c is List ? c.map(file.resolve).toList() : [c];
    final data = BytesBuilder(copy: false);
    for (final p in parts.whereType<PdfStream>()) {
      data
        ..add(file.decode(p))
        ..addByte(0x0a);
    }
    _run(data.takeBytes(), resources, 0);
    return List.of(_out);
  }

  void _run(Uint8List data, PdfDict res, int depth) {
    final lx = PdfLexer(data);
    final ops = <Object?>[];
    for (var t = lx.object(); t != PdfLexer.eof; t = lx.object()) {
      if (t is! PdfOp) {
        ops.add(t);
        continue;
      }
      if (t.op == 'BI') _skipInlineImage(lx);
      _op(t.op, ops, res, depth);
      ops.clear();
    }
  }

  void _skipInlineImage(PdfLexer lx) {
    final b = lx.bytes;
    var i = lx.pos;
    while (i + 2 < b.length &&
        !(b[i] == 0x45 &&
            b[i + 1] == 0x49 &&
            b[i - 1] <= 0x20 &&
            b[i + 2] <= 0x20)) {
      i++;
    }
    lx.pos = i + 2;
  }

  double _n(List<Object?> o, int i) =>
      i < o.length && o[i] is num ? (o[i]! as num).toDouble() : 0;

  void _op(String op, List<Object?> o, PdfDict res, int depth) {
    switch (op) {
      case 'q':
        _stack.add((_ctm, _fill));
      case 'Q':
        if (_stack.isNotEmpty) _restore(_stack.removeLast());
      case 'cm':
        _ctm = _mul([for (var i = 0; i < 6; i++) _n(o, i)], _ctm);
      case 'g':
        _fill = _rgb(_n(o, 0), _n(o, 0), _n(o, 0));
      case 'rg':
        _fill = _rgb(_n(o, 0), _n(o, 1), _n(o, 2));
      case 'k':
        _fill = _cmyk(o);
      case 'sc' || 'scn':
        final nums = o.whereType<num>().length;
        if (o.isNotEmpty && o.last is PdfName) break;
        _fill = switch (nums) {
          1 => _rgb(_n(o, 0), _n(o, 0), _n(o, 0)),
          3 => _rgb(_n(o, 0), _n(o, 1), _n(o, 2)),
          4 => _cmyk(o),
          _ => _fill,
        };
      case 'BT':
        _tm = _tlm = _identity;
      case 'Tf':
        _size = _n(o, 1);
        final fonts = file.dict(res['Font']);
        final name = o.isEmpty ? null : o[0];
        _font = name is PdfName ? _fontFor(fonts?[name.name]) : null;
      case 'Tc':
        _tc = _n(o, 0);
      case 'Tw':
        _tw = _n(o, 0);
      case 'Tz':
        _th = _n(o, 0) / 100;
      case 'TL':
        _tl = _n(o, 0);
      case 'Ts':
        _rise = _n(o, 0);
      case 'Td':
        _move(_n(o, 0), _n(o, 1));
      case 'TD':
        _tl = -_n(o, 1);
        _move(_n(o, 0), _n(o, 1));
      case 'Tm':
        _tm = _tlm = [for (var i = 0; i < 6; i++) _n(o, i)];
      case 'T*':
        _move(0, -_tl);
      case 'Tj':
        _show(o.isEmpty ? null : o[0]);
      case "'":
        _move(0, -_tl);
        _show(o.isEmpty ? null : o[0]);
      case '"':
        _tw = _n(o, 0);
        _tc = _n(o, 1);
        _move(0, -_tl);
        _show(o.length > 2 ? o[2] : null);
      case 'TJ':
        final arr = o.isEmpty ? null : o[0];
        if (arr is! List) break;
        for (final item in arr) {
          if (item is num) {
            _advance(-item.toDouble() / 1000 * _size * _th);
          } else {
            _show(item);
          }
        }
      case 'Do':
        _form(o.isEmpty ? null : o[0], res, depth);
    }
  }

  int _cmyk(List<Object?> o) {
    final k = _n(o, 3);
    return _rgb(
      (1 - _n(o, 0)) * (1 - k),
      (1 - _n(o, 1)) * (1 - k),
      (1 - _n(o, 2)) * (1 - k),
    );
  }

  PdfFont? _fontFor(Object? ref) {
    final d = file.dict(ref);
    if (d == null) return null;
    return _fonts.putIfAbsent(
      ref is PdfRef ? ref.num : d,
      () => PdfFont(file, d),
    );
  }

  void _move(double tx, double ty) {
    _tlm = _mul([1, 0, 0, 1, tx, ty], _tlm);
    _tm = _tlm;
  }

  void _advance(double tx) => _tm = _mul([1, 0, 0, 1, tx, 0], _tm);

  void _show(Object? s) {
    final font = _font;
    if (s is! PdfString || font == null) return;
    final m = _mul([_size * _th, 0, 0, _size, 0, _rise], _mul(_tm, _ctm));
    final x0 = m[4];
    final y = m[5];
    final size = math.sqrt(m[2] * m[2] + m[3] * m[3]);
    final text = StringBuffer();
    for (final g in font.decode(s.bytes)) {
      text.write(g.text);
      final w = g.width / 1000 * _size + _tc + (g.isSpace ? _tw : 0);
      _advance(w * _th);
    }
    final x1 = _mul(_tm, _ctm)[4];
    if (text.isEmpty || _fill == 0xffffff) return;
    _out.add((text: '$text', x0: x0, x1: x1, y: y, size: size, rgb: _fill));
  }

  void _form(Object? name, PdfDict res, int depth) {
    if (name is! PdfName || depth > 8) return;
    final xo = file.dict(res['XObject']);
    final form = file.resolve(xo?[name.name]);
    if (form is! PdfStream || nameOf(form.dict['Subtype']) != 'Form') return;
    final saved = (_ctm, _fill);
    final matrix = file.resolve(form.dict['Matrix']);
    if (matrix is List && matrix.length == 6) {
      _ctm = _mul([for (final v in matrix) (v as num?)?.toDouble() ?? 0], _ctm);
    }
    _run(
      file.decode(form),
      file.dict(form.dict['Resources']) ?? res,
      depth + 1,
    );
    _restore(saved);
  }

  void _restore((_M, int?) state) {
    _ctm = state.$1;
    _fill = state.$2;
  }
}
