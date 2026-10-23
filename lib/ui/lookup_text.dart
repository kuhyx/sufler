import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// What was long-pressed: the [word], the [sentence] around it, and the
/// character [offset] in the text.
typedef LookupPick = ({String word, String sentence, int offset});

final _wordChar = RegExp(r"[\p{L}\p{N}'-]", unicode: true);
final _sentenceEnd = RegExp(r'[.!?…\n]');

bool _isWord(String text, int i) =>
    i >= 0 && i < text.length && _wordChar.hasMatch(text[i]);

/// The word of [text] at [offset] (or just before it), with the sentence
/// around it; null when there is no word there.
LookupPick? pickAt(String text, int offset) {
  var at = offset;
  if (!_isWord(text, at)) at--;
  if (!_isWord(text, at)) return null;
  var start = at;
  var end = at + 1;
  while (_isWord(text, start - 1)) {
    start--;
  }
  while (_isWord(text, end)) {
    end++;
  }
  var from = start;
  while (from > 0 && !_sentenceEnd.hasMatch(text[from - 1])) {
    from--;
  }
  var to = end;
  while (to < text.length && !_sentenceEnd.hasMatch(text[to])) {
    to++;
  }
  if (to < text.length && text[to] != '\n') to++;
  return (
    word: text.substring(start, end),
    sentence: text.substring(from, to).trim(),
    offset: start,
  );
}

/// [text] whose words can be looked up: a long-press on a word calls
/// [onLookup] with it.
class LookupText extends StatefulWidget {
  /// Creates the text.
  const new(this.text, {required this.onLookup, this.style, super.key});

  /// What is shown.
  final String text;

  /// A word was long-pressed.
  final ValueChanged<LookupPick> onLookup;

  /// Text style.
  final TextStyle? style;

  @override
  State<LookupText> createState() => _LookupTextState();
}

class _LookupTextState extends State<LookupText> {
  final GlobalKey _key = GlobalKey();

  static RenderParagraph? _paragraph(RenderObject? o) {
    if (o is RenderParagraph) return o;
    RenderParagraph? found;
    o?.visitChildren((c) => found ??= _paragraph(c));
    return found;
  }

  void _pressed(LongPressStartDetails d) {
    final p = _paragraph(_key.currentContext?.findRenderObject());
    if (p == null) return;
    final at = p.getPositionForOffset(p.globalToLocal(d.globalPosition));
    final pick = pickAt(widget.text, at.offset);
    if (pick != null) widget.onLookup(pick);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: _pressed,
    child: Text(widget.text, key: _key, style: widget.style),
  );
}
