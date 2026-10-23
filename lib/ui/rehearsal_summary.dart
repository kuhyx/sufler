import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/session.dart';

/// End of the rehearsal: per-pass scores and "again".
class RehearsalSummary extends StatelessWidget {
  /// Creates the summary.
  const RehearsalSummary({
    required this.session,
    required this.onAgain,
    super.key,
  });

  /// The finished session.
  final RehearsalSession session;

  /// Start over.
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final reached = s.loop && s.cleanStreak >= s.cleanTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Koniec', style: Theme.of(context).textTheme.headlineSmall),
        if (reached)
          Text('Czyste przebiegi z rzędu: ${s.cleanTarget}. Umiesz to!'),
        const SizedBox(height: AppSpacing.md),
        for (final (i, p) in s.history.indexed)
          ListTile(
            dense: true,
            leading: Icon(p.clean ? Icons.check_circle : Icons.cancel),
            title: Text('Przebieg ${i + 1}: $p'),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onAgain,
          icon: const Icon(Icons.replay),
          label: const Text('Jeszcze raz'),
        ),
      ],
    );
  }
}
