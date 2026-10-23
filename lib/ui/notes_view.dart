import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/script.dart';

/// Shows the notes of [lines] (line -> its notes) under [title]; each
/// line's text heads its notes when there are several lines.
Future<void> showNotes(
  BuildContext context,
  String title,
  Map<ScriptLine, List<LineNote>> lines,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in lines.entries) ...[
              if (lines.length > 1)
                Text(
                  e.key.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.labelLarge,
                ),
              for (final n in e.value) ...[
                Text('„${n.about}”', style: theme.titleSmall),
                Text(n.text),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zamknij'),
        ),
      ],
    );
  },
);

/// The note mark: a lightbulb with how many notes; tap to read them.
class NotesButton extends StatelessWidget {
  /// Creates the mark for [count] notes, labelled [tooltip].
  const new({
    required this.count,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  /// Number of notes.
  final int count;

  /// Accessible label.
  final String tooltip;

  /// Opens the notes.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Badge(
      label: Text('$count'),
      child: const Icon(Icons.lightbulb_outline),
    ),
  );
}

/// The notes of the lines from [start] to [end] of [script].
Map<ScriptLine, List<LineNote>> notesIn(
  Script script,
  Map<int, List<LineNote>> notes,
  int start,
  int end,
) => {
  for (final e in notes.entries)
    if (e.key >= start && e.key <= end && e.key < script.lines.length)
      script.lines[e.key]: e.value,
};

/// Opens the notes of a section (scene/song list).
void openSectionNotes(
  BuildContext context,
  String title,
  Map<ScriptLine, List<LineNote>> lines,
) => unawaited(showNotes(context, 'Notatki: $title', lines));
