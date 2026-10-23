import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/storage/prefs.dart';

/// After the actor said their line: the text revealed, what the mic heard,
/// and ✓/✗ with the suggested grade pre-selected (Enter confirms it).
class GradeView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.cue,
    required this.visibility,
    required this.heard,
    required this.suggestion,
    required this.onGrade,
    this.trailing,
    super.key,
  });

  /// The own line just said.
  final Cue cue;

  /// Own-line text visibility.
  final TextVisibility visibility;

  /// Transcript of what was said, if any.
  final String? heard;

  /// Pre-selected grade, if any.
  final bool? suggestion;

  /// The actor's grade.
  final ValueChanged<bool> onGrade;

  /// Extra widget beside the text (play my recording).
  final Widget? trailing;

  Widget _button({required bool ok}) {
    final icon = Icon(ok ? Icons.check : Icons.close);
    final label = Text(ok ? 'Dobrze' : 'Źle');
    void tap() => onGrade(ok);
    final picked = suggestion == ok;
    final key = Key(ok ? 'grade-ok' : 'grade-bad');
    return picked || (suggestion == null && ok)
        ? FilledButton.icon(key: key, onPressed: tap, icon: icon, label: label)
        : OutlinedButton.icon(
            key: key,
            onPressed: tap,
            icon: icon,
            label: label,
          );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hidden = visibility == TextVisibility.hide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Jak poszło?', style: theme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(hidden ? '…' : cue.text, style: theme.headlineSmall),
            ),
            ?trailing,
          ],
        ),
        if (heard != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Usłyszałem: „$heard”', key: const Key('heard')),
        ],
        if (suggestion != null)
          Text(
            suggestion!
                ? 'Wygląda dobrze — Enter potwierdza ✓'
                : 'Enter potwierdza ✗',
            style: theme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: _button(ok: false)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _button(ok: true)),
          ],
        ),
      ],
    );
  }
}
