import 'dart:typed_data';

import 'package:sufler/import/readers/zip_entry.dart';
import 'package:sufler/import/styled_line.dart';
import 'package:xml/xml.dart';

/// Reads `content.xml`: one line per `text:p` / `text:h` and per
/// `text:line-break`, coloured by the automatic styles' `fo:color`.
List<StyledLine> readOdt(Uint8List bytes) {
  final doc = XmlDocument.parse(zipText(bytes, 'content.xml'));
  return _OdtWalker(_styleColours(doc)).walk(doc.rootElement);
}

/// style:name -> colour, following style:parent-style-name.
Map<String, int?> _styleColours(XmlDocument doc) {
  final own = <String, int?>{};
  final parent = <String, String>{};
  for (final s in doc.descendants.whereType<XmlElement>()) {
    if (s.localName != 'style') continue;
    final name = _attr(s, 'name');
    if (name == null) continue;
    final up = _attr(s, 'parent-style-name');
    if (up != null) parent[name] = up;
    for (final p in s.childElements) {
      if (p.localName == 'text-properties') {
        own[name] = parseHexColour(_attr(p, 'color'));
      }
    }
  }
  int? resolve(String name, int depth) {
    if (own.containsKey(name) || depth > 8) return own[name];
    final up = parent[name];
    return up == null ? null : resolve(up, depth + 1);
  }

  return {
    for (final n in {...own.keys, ...parent.keys}) n: resolve(n, 0),
  };
}

String? _attr(XmlElement e, String local) =>
    e.attributes.where((a) => a.localName == local).firstOrNull?.value;

class _OdtWalker {
  new(this.colours);

  final Map<String, int?> colours;
  final List<StyledLine> lines = [];
  List<TextRun> runs = [];

  List<StyledLine> walk(XmlElement root) {
    _blocks(root);
    return lines;
  }

  void _blocks(XmlElement e) {
    for (final c in e.childElements) {
      if (c.localName == 'p' || c.localName == 'h') {
        runs = [];
        _inline(c, _colourOf(c, null));
        lines.add(StyledLine.fromRuns(runs));
      } else if (c.localName != 'automatic-styles' &&
          c.localName != 'font-face-decls') {
        _blocks(c);
      }
    }
  }

  int? _colourOf(XmlElement e, int? inherited) {
    final style = _attr(e, 'style-name');
    if (style == null || !colours.containsKey(style)) return inherited;
    return colours[style] ?? inherited;
  }

  void _inline(XmlElement e, int? colour) {
    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        runs.add(TextRun(node.value ?? '', colour));
      } else if (node is XmlElement) {
        switch (node.localName) {
          case 's':
            final n = int.tryParse(_attr(node, 'c') ?? '') ?? 1;
            runs.add(TextRun(' ' * n, colour));
          case 'tab':
            runs.add(TextRun('\t', colour));
          case 'line-break':
            lines.add(StyledLine.fromRuns(runs));
            runs = [];
          case 'note' || 'annotation' || 'bookmark' || 'soft-page-break':
            break;
          default:
            _inline(node, _colourOf(node, colour));
        }
      }
    }
  }
}
