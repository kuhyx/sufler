import 'dart:convert';
import 'dart:typed_data';

import 'package:sufler/import/pdf/pdf_objects.dart';

export 'package:sufler/import/pdf/pdf_objects.dart';

bool _isWhite(int c) =>
    c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 || c == 0x0c || c == 0;

bool _isDelim(int c) => '()<>[]{}/%'.codeUnits.contains(c);

/// Tokenizer and object parser for PDF syntax (files and content streams).
class PdfLexer {
  /// Lexes [bytes] from [pos].
  PdfLexer(this.bytes, [this.pos = 0]);

  /// Source bytes.
  final Uint8List bytes;

  /// Current offset.
  int pos;

  final List<Object?> _back = [];

  /// End of input marker returned by [token].
  static const eof = PdfOp('');

  void _skipSpace() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0a && bytes[pos] != 0x0d) {
          pos++;
        }
      } else {
        return;
      }
    }
  }

  /// Next raw token: num, [PdfName], [PdfString] or [PdfOp].
  Object? token() {
    if (_back.isNotEmpty) return _back.removeLast();
    _skipSpace();
    if (pos >= bytes.length) return eof;
    final c = bytes[pos];
    if (c == 0x2f) return _name();
    if (c == 0x28) return _literal();
    if (c == 0x3c) {
      if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3c) {
        pos += 2;
        return const PdfOp('<<');
      }
      return _hex();
    }
    if (c == 0x3e && pos + 1 < bytes.length && bytes[pos + 1] == 0x3e) {
      pos += 2;
      return const PdfOp('>>');
    }
    if (_isDelim(c)) {
      pos++;
      return PdfOp(String.fromCharCode(c));
    }
    final start = pos;
    while (pos < bytes.length &&
        !_isWhite(bytes[pos]) &&
        !_isDelim(bytes[pos])) {
      pos++;
    }
    final word = latin1.decode(bytes.sublist(start, pos));
    return num.tryParse(word) ?? _number(word) ?? PdfOp(word);
  }

  num? _number(String w) =>
      RegExp(r'^[+-]?\d*\.?\d*$').hasMatch(w) && w.contains(RegExp(r'\d'))
      ? double.tryParse(
          '${w.replaceFirst(RegExp(r'^\+'), '')}${w.endsWith('.') ? '0' : ''}',
        )
      : null;

  /// Pushes [t] back so the next [token] returns it.
  void unread(Object? t) => _back.add(t);

  PdfName _name() {
    pos++;
    final out = <int>[];
    while (pos < bytes.length &&
        !_isWhite(bytes[pos]) &&
        !_isDelim(bytes[pos])) {
      if (bytes[pos] == 0x23 && pos + 2 < bytes.length) {
        final h = int.tryParse(
          latin1.decode(bytes.sublist(pos + 1, pos + 3)),
          radix: 16,
        );
        if (h != null) {
          out.add(h);
          pos += 3;
          continue;
        }
      }
      out.add(bytes[pos++]);
    }
    return PdfName(utf8.decode(out, allowMalformed: true));
  }

  PdfString _literal() {
    pos++;
    final out = <int>[];
    var depth = 1;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x5c && pos < bytes.length) {
        final e = bytes[pos++];
        const esc = {0x6e: 10, 0x72: 13, 0x74: 9, 0x62: 8, 0x66: 12};
        if (esc.containsKey(e)) {
          out.add(esc[e]!);
        } else if (e >= 0x30 && e <= 0x37) {
          var v = e - 0x30;
          for (var i = 0; i < 2 && pos < bytes.length; i++) {
            final d = bytes[pos];
            if (d < 0x30 || d > 0x37) break;
            v = v * 8 + d - 0x30;
            pos++;
          }
          out.add(v & 0xff);
        } else if (e == 0x0d) {
          if (pos < bytes.length && bytes[pos] == 0x0a) pos++;
        } else if (e != 0x0a) {
          out.add(e);
        }
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29 && --depth == 0) break;
      out.add(c);
    }
    return PdfString(Uint8List.fromList(out));
  }

  PdfString _hex() {
    pos++;
    final digits = StringBuffer();
    while (pos < bytes.length && bytes[pos] != 0x3e) {
      final c = bytes[pos++];
      if (!_isWhite(c)) digits.writeCharCode(c);
    }
    pos++;
    var hex = digits.toString();
    if (hex.length.isOdd) hex += '0';
    return PdfString(
      Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.tryParse(hex.substring(i, i + 2), radix: 16) ?? 0,
      ]),
    );
  }

  /// Parses one object; arrays and dicts recurse, `n g R` becomes [PdfRef].
  Object? object() {
    final t = token();
    if (t is PdfOp) {
      switch (t.op) {
        case '[':
          final list = <Object?>[];
          for (var x = object(); !_isOp(x, ']') && x != eof; x = object()) {
            list.add(x);
          }
          return list;
        case '<<':
          final dict = <String, Object?>{};
          for (var k = object(); k is PdfName; k = object()) {
            dict[k.name] = object();
          }
          return dict;
        case 'true' || 'false':
          return t.op == 'true';
        case 'null':
          return null;
      }
      return t;
    }
    if (t is int && t >= 0) {
      final g = token();
      if (g is int) {
        final r = token();
        if (_isOp(r, 'R')) return PdfRef(t, g);
        unread(r);
      }
      unread(g);
    }
    return t;
  }

  static bool _isOp(Object? x, String op) => x is PdfOp && x.op == op;
}
