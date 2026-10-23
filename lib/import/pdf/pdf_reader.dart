import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sufler/import/pdf/pdf_file.dart';
import 'package:sufler/import/pdf/pdf_text.dart';
import 'package:sufler/import/styled_line.dart';

/// Reads a PDF into coloured visual lines, top to bottom, page by page.
///
/// Pure Dart (runs on the web): see [PdfFile] and [PdfTextExtractor].
/// A blank [StyledLine] marks a paragraph gap; [StyledLine.wraps] marks a
/// line that runs to the right margin and continues on the next one.
List<StyledLine> readPdf(Uint8List bytes) {
  if (!String.fromCharCodes(bytes.take(1024)).contains('%PDF')) {
    throw const FormatException('Not a PDF file');
  }
  final file = PdfFile(bytes);
  final extractor = PdfTextExtractor(file);
  final out = <StyledLine>[];
  for (final (page, res) in file.pages()) {
    final lines = _lines(extractor.page(page, res));
    if (lines.isEmpty) continue;
    final left = lines.map((l) => l.x0).reduce(math.min);
    final right = lines.map((l) => l.x1).reduce(math.max);
    final nearRight = right - (right - left) * 0.15;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      final gap = next == null ? 0 : l.y - next.y;
      final blank = next != null && gap > l.size * 1.9;
      out.add(StyledLine.fromRuns(l.runs, wraps: !blank && l.x1 >= nearRight));
      if (blank) out.add(const StyledLine(''));
    }
  }
  return out;
}

class _Line {
  _Line(TextChunk c) : y = c.y, size = c.size {
    chunks.add(c);
  }

  final double y;
  double size;
  final List<TextChunk> chunks = [];

  double get x0 => chunks.first.x0;
  double get x1 => chunks.map((c) => c.x1).reduce(math.max);

  late final List<TextRun> runs = _join();

  List<TextRun> _join() {
    chunks.sort((a, b) => a.x0.compareTo(b.x0));
    final runs = <TextRun>[];
    TextChunk? prev;
    for (final c in chunks) {
      if (prev != null) {
        final gap = c.x0 - prev.x1;
        // Overprinted duplicates (fake bold) are dropped.
        if (gap < -c.size * 0.5 && c.text == prev.text) continue;
        final spaced = prev.text.endsWith(' ') || c.text.startsWith(' ');
        if (gap > c.size * 0.15 && !spaced) runs.add(TextRun(' ', c.rgb));
      }
      runs.add(TextRun(c.text, c.rgb));
      prev = c;
    }
    return runs;
  }
}

List<_Line> _lines(List<TextChunk> chunks) {
  final sorted = [...chunks]..sort((a, b) => b.y.compareTo(a.y));
  final lines = <_Line>[];
  for (final c in sorted) {
    final last = lines.isEmpty ? null : lines.last;
    final tolerance = math.max(last?.size ?? 0, c.size) * 0.4;
    if (last != null && (last.y - c.y).abs() <= tolerance) {
      last
        ..chunks.add(c)
        ..size = math.max(last.size, c.size);
    } else {
      lines.add(_Line(c));
    }
  }
  return lines
      .where((l) => l.chunks.any((c) => c.text.trim().isNotEmpty))
      .toList();
}
