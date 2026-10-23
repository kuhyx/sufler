import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reads [name] from the zip [bytes] as UTF-8 text.
///
/// Throws a [FormatException] when the file is not a zip or lacks [name].
String zipText(Uint8List bytes, String name) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object catch (e) {
    throw FormatException('Not a zip document: $e');
  }
  final entry = archive.findFile(name);
  if (entry == null) throw FormatException('Document has no $name');
  return utf8.decode(entry.content, allowMalformed: true);
}

/// Parses `#rrggbb` / `rrggbb` into 0xRRGGBB; null for `auto` or junk.
int? parseHexColour(String? value) {
  if (value == null) return null;
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6) return null;
  return int.tryParse(hex, radix: 16);
}
