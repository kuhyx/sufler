import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/labels.dart';

/// Glyph of a line kind; [kindLabel] stays its spoken name.
IconData kindIcon(LineKind kind) => switch (kind) {
  LineKind.dialogue => Icons.chat_bubble_outline,
  LineKind.song => Icons.music_note_outlined,
  LineKind.recitation => Icons.campaign_outlined,
  LineKind.direction => Icons.directions_walk,
  LineKind.heading => Icons.title,
};

/// A line kind as its glyph, spoken as its Polish name.
Widget kindGlyph(LineKind kind, {double? size}) =>
    Icon(kindIcon(kind), size: size, semanticLabel: kindLabel(kind));

/// Who says [lines]: the speakers' names (script content) and, when any
/// line is unattributed, a groups glyph for the chorus instead of a word.
/// [extra] follows the names (e.g. a song title, also content).
class Who extends StatelessWidget {
  /// Speakers of [lines] in [script].
  const new(this.script, this.lines, {this.style, this.extra, super.key});

  /// The script.
  final Script script;

  /// The lines whose speakers are shown.
  final Iterable<ScriptLine> lines;

  /// Text style of the names.
  final TextStyle? style;

  /// Content shown after the names.
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final names = <String>[];
    var chorus = false;
    for (final l in lines) {
      if (l.speakers.isEmpty) chorus = true;
      if (l.speakers.isEmpty) continue;
      for (final n in speakerNames(script, l).split(', ')) {
        if (!names.contains(n)) names.add(n);
      }
    }
    final size = (style ?? DefaultTextStyle.of(context).style).fontSize;
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (names.isNotEmpty) Text(names.join(', '), style: style),
        if (chorus)
          Icon(
            Icons.groups,
            size: size == null ? null : size * 1.3,
            semanticLabel: 'Chór',
          ),
        if (extra != null) Text('· $extra', style: style),
      ],
    );
  }
}
