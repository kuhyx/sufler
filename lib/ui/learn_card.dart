import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/sections_tab.dart';
import 'package:sufler/ui/spoken.dart';

/// The one-tap way into learning: continue where the last rehearsal
/// stopped, or start with the first scene that has my lines.
class LearnCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.script,
    required this.prefs,
    required this.onResume,
    required this.onStart,
    required this.onRoles,
    super.key,
  });

  /// The script.
  final Script script;

  /// Roles, resume point and knowledge.
  final RehearsalPrefs prefs;

  /// Continue [RehearsalPrefs.resume].
  final ValueChanged<ResumePoint> onResume;

  /// Start a section from its beginning.
  final RangeAction onStart;

  /// Open "Moje role".
  final VoidCallback onRoles;

  Section? get _firstWithMine => script.scenes
      .where((s) => ownLines(script, prefs, LineRange.section(s)).isNotEmpty)
      .firstOrNull;

  /// [s] as its tab glyph and its tile number (the grid numbers them).
  Widget _section(Section s) {
    final song = script.songs.contains(s);
    final list = song ? script.songs : script.scenes;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        Icon(song ? Icons.music_note : Icons.theaters, size: 18),
        Text('${list.indexOf(s) + 1}'),
      ],
    );
  }

  /// Where [r] resumes: its section, a missed-only glyph, or the bare line
  /// range.
  Widget _where(ResumePoint r) {
    if (r.missedOnly) return const Icon(Icons.history, size: 18);
    final section = [
      ...script.scenes,
      ...script.songs,
    ].where((s) => s.start == r.start && s.end == r.end).firstOrNull;
    return section == null ? Text('${r.start}–${r.end}') : _section(section);
  }

  @override
  Widget build(BuildContext context) {
    final resume = prefs.resume;
    final first = _firstWithMine;
    final Widget action;
    if (prefs.roles.isEmpty) {
      action = FilledButton(
        key: const Key('learn_roles'),
        onPressed: onRoles,
        child: const Icon(
          Icons.person_outline,
          semanticLabel: 'Wybierz swoje role',
        ),
      );
    } else if (resume != null) {
      action = FilledButton.icon(
        key: const Key('learn'),
        onPressed: () => onResume(resume),
        icon: const Icon(Icons.play_arrow),
        label: Spoken(
          semanticLabel:
              'Ucz się dalej: ${resume.label} · kwestia ${resume.position + 1}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.xs,
            children: [
              Flexible(child: _where(resume)),
              const Icon(Icons.flag_outlined, size: 18),
              Text('${resume.position + 1}'),
            ],
          ),
        ),
      );
    } else if (first != null) {
      action = FilledButton.icon(
        key: const Key('learn'),
        onPressed: () => onStart(LineRange.section(first), first.title),
        icon: const Icon(Icons.play_arrow),
        label: Spoken(
          semanticLabel: 'Zacznij naukę: ${first.title}',
          child: _section(first),
        ),
      );
    } else {
      action = Icon(
        Icons.info_outline,
        size: 64,
        color: Theme.of(context).colorScheme.outline,
        semanticLabel: 'Twoje role nie mają kwestii w scenach.',
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: action,
    );
  }
}
