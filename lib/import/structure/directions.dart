/// Stage-direction handling: `( … )` and whole-line `/cue/` are kept as
/// directions; the `/.../` pause marker is dropped.
library;

final _pause = RegExp(r'/\s*(\.{2,}|…)\s*/');
final _slashCue = RegExp(r'^\s*/([^/]+)/\s*$', multiLine: true);
// An opening `/` whose closing one the author forgot: cue runs to the end.
final _openCue = RegExp(r'(^|\n)\s*/[^/]+$');

/// Removes stage directions from [text]. Returns the remaining text (line
/// breaks kept, blank lines dropped) and the directions in order.
(String, List<String>) splitDirections(String text) {
  final directions = <String>[];
  final kept = StringBuffer();
  var depth = 0;
  var current = StringBuffer();
  for (final ch in text.split('')) {
    if (ch == '(') {
      if (depth == 0) current = StringBuffer();
      depth++;
    }
    if (depth > 0) {
      current.write(ch);
      if (ch == ')' && --depth == 0) directions.add(_squash('$current'));
    } else {
      kept.write(ch);
    }
  }
  if (depth > 0) directions.add(_squash('$current'));
  var rest = kept.toString().replaceAll(_pause, ' ');
  rest = rest.replaceAllMapped(_slashCue, (m) {
    directions.add(_squash(m[0]!));
    return '';
  });
  rest = rest.replaceAllMapped(_openCue, (m) {
    directions.add(_squash(m[0]!));
    return '';
  });
  final lines = rest
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .map((l) => l.replaceAllMapped(RegExp(' ([,.!?;:…])'), (m) => m[1]!))
      .map((l) => l.replaceAllMapped(RegExp(r'([!?])\.(?!\.)'), (m) => m[1]!))
      .where((l) => l.isNotEmpty && !RegExp(r'^[,.;:]+$').hasMatch(l));
  final out = lines.join('\n').replaceFirst(RegExp(r'^[,;:]\s*'), '');
  return (out, directions);
}

String _squash(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
