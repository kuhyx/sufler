import 'dart:typed_data';

import 'package:sufler/import/readers/zip_entry.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:xml/xml.dart';

/// Reads `word/document.xml`: one line per paragraph and per `w:br`, with
/// each run's `w:color`.
List<StyledLine> readDocx(Uint8List bytes) {
  final doc = XmlDocument.parse(zipText(bytes, 'word/document.xml'));
  final lines = <StyledLine>[];
  for (final p in doc.descendants.whereType<XmlElement>()) {
    if (p.localName != 'p') continue;
    var runs = <TextRun>[];
    for (final r in p.descendants.whereType<XmlElement>()) {
      if (r.localName != 'r') continue;
      final colour = _runColour(r);
      for (final child in r.childElements) {
        switch (child.localName) {
          case 't':
            runs.add(TextRun(child.innerText, colour));
          case 'tab':
            runs.add(TextRun('\t', colour));
          case 'br' || 'cr':
            lines.add(StyledLine.fromRuns(runs));
            runs = [];
        }
      }
    }
    lines.add(StyledLine.fromRuns(runs));
  }
  return lines;
}

int? _runColour(XmlElement run) {
  for (final props in run.childElements) {
    if (props.localName != 'rPr') continue;
    for (final c in props.childElements) {
      if (c.localName != 'color') continue;
      final val = c.attributes
          .where((a) => a.localName == 'val')
          .map((a) => a.value)
          .firstOrNull;
      return parseHexColour(val);
    }
  }
  return null;
}
