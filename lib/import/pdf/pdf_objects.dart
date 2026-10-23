import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A PDF name object (`/Font`), stored without the slash.
@immutable
class PdfName {
  /// Creates a name.
  const PdfName(this.name);

  /// The decoded name.
  final String name;

  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '/$name';
}

/// A PDF string object: raw bytes, decoded later by the font.
@immutable
class PdfString {
  /// Creates a string.
  const PdfString(this.bytes);

  /// The raw bytes.
  final Uint8List bytes;
}

/// An indirect reference `num gen R`.
@immutable
class PdfRef {
  /// Creates a reference.
  const PdfRef(this.num, this.gen);

  /// Object number.
  final int num;

  /// Generation number.
  final int gen;
}

/// A bare keyword: content operator, `obj`, `stream`, `[`, `<<`...
@immutable
class PdfOp {
  /// Creates a keyword.
  const PdfOp(this.op);

  /// The keyword text.
  final String op;

  @override
  String toString() => op;
}

/// A PDF dictionary.
typedef PdfDict = Map<String, Object?>;
