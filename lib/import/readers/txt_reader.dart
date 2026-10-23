import 'dart:convert';
import 'dart:typed_data';

import 'package:sufler/import/styled_line.dart';

/// Reads a plain-text script: UTF-8 (BOM tolerated), one line per line.
List<StyledLine> readTxt(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  return [
    for (final line in text.split(RegExp(r'\r\n|\r|\n'))) StyledLine(line),
  ];
}
