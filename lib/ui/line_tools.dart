import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/assist/line_voices.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/ui/notes_view.dart';
import 'package:sufler/ui/rehearsal_assist.dart';

/// Under the current cue's label: ✎ (correct it), the note mark, and
/// whether it was corrected / is said by device TTS until re-rendered.
class LineTools extends StatelessWidget {
  /// Creates the row for [cue].
  const new({required this.cue, required this.assist, super.key});

  /// The current cue.
  final Cue cue;

  /// Corrections and notes.
  final RehearsalAssist assist;

  Future<void> _edit(BuildContext context) async {
    var line = cue.line;
    if (cue.following.isNotEmpty) {
      final picked = await showDialog<ScriptLine>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Którą kwestię poprawić?'),
          children: [
            for (final l in cue.lines)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(l),
                child: Text(
                  l.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
      if (picked == null || !context.mounted) return;
      line = picked;
    }
    await assist.edit(context, line);
  }

  @override
  Widget build(BuildContext context) {
    final lines = [for (final l in cue.lines) l.index];
    final count = assist.noteCount(cue);
    final small = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        IconButton(
          tooltip: 'Popraw kwestię',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => unawaited(_edit(context)),
        ),
        if (count > 0)
          NotesButton(
            count: count,
            tooltip: 'Notatki ($count)',
            onPressed: () => assist.showCueNotes(context, cue),
          ),
        if (lines.any(assist.edited.contains))
          Text('zmieniono', key: const Key('edited'), style: small),
        if (lines.any(assist.ttsLines.contains))
          Text(ttsUntilRendered, style: small),
      ],
    );
  }
}
