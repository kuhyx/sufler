import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/notes_view.dart';
import 'package:sufler/ui/pure_run.dart';
import 'package:sufler/ui/song_preview.dart';

/// Starts something over a range, titled with the label.
typedef RangeAction = void Function(LineRange range, String label);

/// Own spoken lines in [range] under [prefs]' roles.
List<ScriptLine> ownLines(Script s, RehearsalPrefs prefs, LineRange range) => [
  for (var i = range.start; i <= range.end && i < s.lines.length; i++)
    if (isMine(s.lines[i], prefs.roles)) s.lines[i],
];

/// One tab of sections (scenes or songs): tap to rehearse, the mic to
/// record the timings of my lines in it. [header] goes above the list.
class SectionsTab extends StatelessWidget {
  /// Creates the tab.
  const new({
    required this.script,
    required this.sections,
    required this.icon,
    required this.prefs,
    required this.onStart,
    required this.onRecord,
    this.header = const [],
    this.songs = false,
    super.key,
  });

  /// The script.
  final Script script;

  /// Scenes or songs.
  final List<Section> sections;

  /// Leading icon of each tile.
  final IconData icon;

  /// Roles and knowledge.
  final RehearsalPrefs prefs;

  /// Rehearse a section.
  final RangeAction onStart;

  /// Record the timings of my lines in a section.
  final RangeAction onRecord;

  /// Widgets above the list.
  final List<Widget> header;

  /// Song tiles also say who sings.
  final bool songs;

  Widget _tile(BuildContext context, Section s) {
    final range = LineRange.section(s);
    final mine = ownLines(script, prefs, range);
    final known = mine.where((l) => prefs.knowledge[l.index]?.last ?? false);
    final notes = notesIn(script, prefs.notes, s.start, s.end);
    final count = notes.values.fold(0, (n, list) => n + list.length);
    final parts = [
      'kwestie ${s.start}–${s.end}',
      if (songs) 'śpiewa: ${songSingers(script, s)}',
      if (mine.isNotEmpty) 'umiem ${known.length}/${mine.length}',
    ];
    return ListTile(
      leading: Icon(icon),
      title: SectionTitle(section: s, pure: prefs.pureRuns.contains(s.id)),
      subtitle: Text(parts.join(' · ')),
      onTap: () => onStart(range, s.title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0)
            NotesButton(
              count: count,
              tooltip: 'Notatki: ${s.title} ($count)',
              onPressed: () => openSectionNotes(context, s.title, notes),
            ),
          if (mine.isNotEmpty)
            IconButton(
              tooltip: 'Nagraj czasy: ${s.title}',
              icon: const Icon(Icons.mic_none),
              onPressed: () => onRecord(range, s.title),
            ),
          const Icon(Icons.play_arrow),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      ...header,
      if (sections.isEmpty)
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nic tu nie ma',
          message: 'Ten skrypt nie ma takich fragmentów.',
        ),
      for (final s in sections) _tile(context, s),
    ],
  );
}
