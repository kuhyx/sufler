import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/sections_tab.dart';

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

  @override
  Widget build(BuildContext context) {
    final resume = prefs.resume;
    final first = _firstWithMine;
    final Widget action;
    if (prefs.roles.isEmpty) {
      action = FilledButton.icon(
        onPressed: onRoles,
        icon: const Icon(Icons.person_outline),
        label: const Text('Wybierz swoje role'),
      );
    } else if (resume != null) {
      action = FilledButton.icon(
        key: const Key('learn'),
        onPressed: () => onResume(resume),
        icon: const Icon(Icons.play_arrow),
        label: Text(
          'Ucz się dalej: ${resume.label} · kwestia ${resume.position + 1}',
        ),
      );
    } else if (first != null) {
      action = FilledButton.icon(
        key: const Key('learn'),
        onPressed: () => onStart(LineRange.section(first), first.title),
        icon: const Icon(Icons.play_arrow),
        label: Text('Zacznij naukę: ${first.title}'),
      );
    } else {
      action = const Text('Twoje role nie mają kwestii w scenach.');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: action,
    );
  }
}
