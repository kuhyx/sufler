import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/run_take.dart';
import 'package:sufler/rehearsal/timing_session.dart';

/// "Nagraj w całości (n kwestie)" at the first line of a run; null
/// elsewhere.
Widget? runOffer(TimingSession s) {
  final n = s.runHere;
  if (n == 0) return null;
  return Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: OutlinedButton.icon(
      key: const Key('record-run'),
      onPressed: s.recordRun,
      icon: const Icon(Icons.queue_music),
      label: Text('Nagraj w całości (${linesLabel(n)})'),
    ),
  );
}

/// A whole run being recorded nonstop (every line shown, "Skończyłem"
/// ends it), or the question before replacing existing recordings.
List<Widget> runViews(BuildContext context, TimingSession s) {
  final theme = Theme.of(context).textTheme;
  if (s.state == TakeState.overwrite) {
    return [
      Text(
        '${s.runExisting} z tych kwestii ma już nagranie.',
        style: theme.titleMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          FilledButton(
            onPressed: () => s.overwrite(yes: true),
            child: const Text('Nadpisz'),
          ),
          OutlinedButton(
            onPressed: () => s.overwrite(yes: false),
            child: const Text('Zachowaj istniejące'),
          ),
        ],
      ),
    ];
  }
  final lines = s.runLines ?? const [];
  return [
    Text('Powiedz (zaśpiewaj) całość bez przerwy:', style: theme.bodySmall),
    Text([for (final l in lines) l.text].join('\n'), style: theme.titleLarge),
    const SizedBox(height: AppSpacing.md),
    // Pauses do not end it: only the tap does.
    const Text('Nagrywam… stuknij „Skończyłem” na końcu.'),
    const SizedBox(height: AppSpacing.md),
    SizedBox(
      height: AppSpacing.xxl * 2,
      child: FilledButton(
        // textStyle, not Text.style: keeps the button's foreground colour.
        style: FilledButton.styleFrom(textStyle: theme.headlineSmall),
        onPressed: s.finished,
        child: const Text('Skończyłem'),
      ),
    ),
  ];
}
