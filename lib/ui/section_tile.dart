import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/line_note.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/notes_view.dart';
import 'package:sufler/ui/pure_run.dart';

/// What a section tile and its details sheet say about one section.
class SectionFacts {
  /// Creates the facts.
  const new({
    required this.section,
    required this.number,
    required this.pure,
    required this.mine,
    required this.known,
    required this.notes,
    this.singers,
  });

  /// The scene or song.
  final Section section;

  /// 1-based position on the tab.
  final int number;

  /// Whether it had a pure run.
  final bool pure;

  /// Number of my own lines in it.
  final int mine;

  /// How many of those I know.
  final int known;

  /// Notes by line.
  final Map<ScriptLine, List<LineNote>> notes;

  /// Who sings (songs only).
  final String? singers;

  /// Total number of notes.
  int get noteCount => notes.values.fold(0, (n, list) => n + list.length);

  /// "umiem k/n".
  String get progress => 'umiem $known/$mine';
}

/// One numbered square of the grid: number, title (with the pure badge) and,
/// when I have own lines, "k/n". Tap rehearses, long-press opens details.
class SectionTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.facts,
    required this.icon,
    required this.onTap,
    required this.onDetails,
    super.key,
  });

  /// The section's facts.
  final SectionFacts facts;

  /// Leading icon.
  final IconData icon;

  /// Rehearse.
  final VoidCallback onTap;

  /// Open the details.
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text('${facts.number}', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: DefaultTextStyle.merge(
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SectionTitle(
                      section: facts.section,
                      pure: facts.pure,
                    ),
                  ),
                ),
              ),
              if (facts.mine > 0)
                Text(
                  '${facts.known}/${facts.mine}',
                  style: theme.textTheme.labelMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the details of a section: title, range, singers, progress, notes
/// and the way to record my timings.
Future<void> showSectionDetails(
  BuildContext context,
  SectionFacts facts, {
  required VoidCallback onRecord,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) {
    final s = facts.section;
    final theme = Theme.of(sheet).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: theme.titleLarge,
              child: SectionTitle(section: s, pure: facts.pure),
            ),
            Text('kwestie ${s.start}–${s.end}'),
            if (facts.singers != null) Text('śpiewa: ${facts.singers}'),
            if (facts.mine > 0) Text(facts.progress),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (facts.noteCount > 0)
                  NotesButton(
                    count: facts.noteCount,
                    tooltip: 'Notatki: ${s.title} (${facts.noteCount})',
                    onPressed: () =>
                        openSectionNotes(sheet, s.title, facts.notes),
                  ),
                if (facts.mine > 0)
                  Tooltip(
                    message: 'Nagraj czasy: ${s.title}',
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        onRecord();
                      },
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Nagraj czasy'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  },
);
