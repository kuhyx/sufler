/// The JSON bodies of `POST /explain` and `POST /render_line`
/// (DOCS-contract.md "Assistant"), shared by the HTTP and relay transports.
library;

import 'package:sufler/model/json.dart';
import 'package:sufler/model/script.dart';

/// Spoken lines of context sent before the line.
const contextBefore = 3;

/// Spoken lines of context sent after the line.
const contextAfter = 1;

/// `{speakers: [display names], text}` of [line].
Json _context(Script script, ScriptLine line) {
  final names = {for (final c in script.characters) c.id: c.name};
  return {
    'speakers': [for (final id in line.speakers) names[id] ?? id],
    'text': line.text,
  };
}

/// What the PC needs to explain [selection] of line [index]: the line, its
/// speakers by name, and the nearest spoken lines around it.
Json explainPayload(Script script, int index, String selection) {
  final lines = script.lines;
  final line = lines[index];
  final before = [
    for (final l in lines.take(index))
      if (l.isSpoken) l,
  ];
  final after = lines.skip(index + 1).where((l) => l.isSpoken);
  return {
    'scriptId': script.id,
    'title': script.title,
    'selection': selection.trim(),
    'line': {'index': index, ..._context(script, line)},
    'before': [
      for (final l in before.skip(
        before.length > contextBefore ? before.length - contextBefore : 0,
      ))
        _context(script, l),
    ],
    'after': [for (final l in after.take(contextAfter)) _context(script, l)],
  };
}

/// `{script, index}`: the script as it is now (edits included), so the PC
/// renders the line's current text in the pack's voice.
Json renderLinePayload(Script script, int index) => {
  'script': script.toJson(),
  'index': index,
};
