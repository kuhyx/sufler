import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/session.dart';
import 'package:sufler/ui/spoken.dart';

/// End of the rehearsal: per-pass scores and "again".
class RehearsalSummary extends StatelessWidget {
  /// Creates the summary.
  const new({required this.session, required this.onAgain, super.key});

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
        const Icon(
          Icons.check_circle_outline,
          size: 32,
          semanticLabel: 'Koniec',
        ),
        if (reached)
          Icon(
            Icons.emoji_events,
            semanticLabel:
                'Czyste przebiegi z rzędu: ${s.cleanTarget}. Umiesz to!',
          ),
        const SizedBox(height: AppSpacing.md),
        for (final (i, p) in s.history.indexed)
          ListTile(
            dense: true,
            leading: Icon(p.clean ? Icons.check_circle : Icons.cancel),
            // The score is a number, so it stays visible; the words are spoken.
            title: Text('$p', semanticsLabel: 'Przebieg ${i + 1}: $p'),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onAgain,
          icon: const Icon(Icons.replay, semanticLabel: 'Jeszcze raz'),
          label: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The line above a rehearsal: pass, position, clean streak, last score.
class RehearsalHeader extends StatelessWidget {
  /// Creates the header of [session].
  const new({required this.session, super.key});

  /// The rehearsal.
  final RehearsalSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final parts = [
      'Przebieg ${s.pass}',
      if (s.phase != Phase.finished)
        'kwestia ${s.position + 1}/${s.cues.length}',
      if (s.loop) 'czyste z rzędu ${s.cleanStreak}/${s.cleanTarget}',
      if (s.history.isNotEmpty && s.phase != Phase.finished)
        'ostatni wynik ${s.history.last}',
    ];
    final small = Theme.of(context).textTheme.bodySmall;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    // Glyph + number pairs; the old words stay the spoken label.
    Widget pair(IconData icon, String n) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xs,
      children: [
        Icon(icon, size: 16, color: color),
        Text(n, style: small),
      ],
    );
    return Spoken(
      semanticLabel: parts.join(' · '),
      child: Wrap(
        key: const Key('rehearsal-header'),
        spacing: AppSpacing.md,
        children: [
          pair(Icons.loop, '${s.pass}'),
          if (s.phase != Phase.finished)
            pair(Icons.flag_outlined, '${s.position + 1}/${s.cues.length}'),
          if (s.loop)
            pair(
              Icons.check_circle_outline,
              '${s.cleanStreak}/${s.cleanTarget}',
            ),
          if (s.history.isNotEmpty && s.phase != Phase.finished)
            pair(Icons.scoreboard_outlined, '${s.history.last}'),
        ],
      ),
    );
  }
}

/// A rehearsal page: [RehearsalHeader] over [child], in a prose-width list.
class RehearsalBody extends StatelessWidget {
  /// Creates the page of [session] around [child].
  const new({required this.session, required this.child, super.key});

  /// The rehearsal.
  final RehearsalSession session;

  /// The current cue or the summary.
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          RehearsalHeader(session: session),
          const Divider(),
          child,
        ],
      ),
    ),
  );
}
