import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/notes_view.dart';
import 'package:sufler/ui/section_tile.dart';
import 'package:sufler/ui/song_preview.dart';

/// Starts something over a range, titled with the label.
typedef RangeAction = void Function(LineRange range, String label);

/// Own spoken lines in [range] under [prefs]' roles.
List<ScriptLine> ownLines(Script s, RehearsalPrefs prefs, LineRange range) => [
  for (var i = range.start; i <= range.end && i < s.lines.length; i++)
    if (isMine(s.lines[i], prefs.roles)) s.lines[i],
];

/// One tab of sections (scenes or songs) as a grid that fits the screen,
/// overflow paged sideways: tap to rehearse, long-press for the details and
/// the recording of my timings. [header] goes above the grid.
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

  /// Widgets above the grid.
  final List<Widget> header;

  /// Song details also say who sings.
  final bool songs;

  SectionFacts _facts(int i) {
    final s = sections[i];
    final mine = ownLines(script, prefs, LineRange.section(s));
    return SectionFacts(
      section: s,
      number: i + 1,
      pure: prefs.pureRuns.contains(s.id),
      mine: mine.length,
      known: mine.where((l) => prefs.knowledge[l.index]?.last ?? false).length,
      notes: notesIn(script, prefs.notes, s.start, s.end),
      singers: songs ? songSingers(script, s) : null,
    );
  }

  Widget _tile(BuildContext context, int i) {
    final facts = _facts(i);
    final s = facts.section;
    final range = LineRange.section(s);
    return SectionTile(
      facts: facts,
      icon: icon,
      onTap: () => onStart(range, s.title),
      onDetails: () => showSectionDetails(
        context,
        facts,
        onRecord: () => onRecord(range, s.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (header.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md).copyWith(bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: header,
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      Expanded(
        child: sections.isEmpty
            ? SingleChildScrollView(
                child: Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                  semanticLabel: 'Nic tu nie ma',
                ),
              )
            : FitGrid(
                columns: MediaQuery.sizeOf(context).width >= wideLayout ? 6 : 3,
                itemCount: sections.length,
                itemBuilder: _tile,
              ),
      ),
    ],
  );
}
