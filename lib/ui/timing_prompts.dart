import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/timing_session.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/spoken.dart';
import 'package:sufler/ui/status_glyph.dart';

/// Tap timing: own text hidden (said from memory); the time from when the
/// line came up to the tap becomes its pause. After a missed take the line
/// may already be under way: the clock runs from when it came up, so only
/// the tap is asked for (a red warning glyph says why).
List<Widget> manualViews(BuildContext context, TimingSession s) {
  final problem = s.problem;
  return [
    Row(
      spacing: AppSpacing.sm,
      children: [
        if (problem != null) statusGlyph(context, problem, ok: false),
        Icon(
          Icons.touch_app_outlined,
          size: 32,
          semanticLabel: problem != null
              ? '$problem. Stuknij, gdy skończysz tę kwestię.'
              : 'Powiedz kwestię i stuknij, gdy skończysz.',
        ),
      ],
    ),
    const SizedBox(height: AppSpacing.md),
    SizedBox(
      height: AppSpacing.xxl * 2,
      child: FilledButton(
        onPressed: s.finished,
        child: const Icon(Icons.check, size: 32, semanticLabel: 'Skończyłem'),
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
  ];
}

/// The take sounded like a later line: its number and text (content), then
/// save-there or redo.
List<Widget> skippedViews(TimingSession s) {
  final other = s.lines[s.skipTo!];
  final at = '${s.skipTo! + 1}/${s.lines.length}';
  return [
    const SizedBox(height: AppSpacing.md),
    Row(
      key: const Key('skip-warning'),
      spacing: AppSpacing.sm,
      children: [
        Icon(
          Icons.fast_forward,
          semanticLabel: 'To brzmi jak kolejna kwestia ($at)',
        ),
        Text(at),
        Expanded(child: Text('„${other.text}”')),
      ],
    ),
    const SizedBox(height: AppSpacing.sm),
    Wrap(
      spacing: AppSpacing.sm,
      children: [
        FilledButton(
          key: const Key('accept-skip'),
          onPressed: s.accept,
          child: const Icon(Icons.check, semanticLabel: 'Tak, zapisz tam'),
        ),
        OutlinedButton(
          key: const Key('redo-skip'),
          onPressed: s.redo,
          child: const Icon(Icons.repeat, semanticLabel: 'Powtórz tę'),
        ),
      ],
    ),
  ];
}

/// The line just saved: a check and its time; spoken as the old sentence.
Widget? savedView(TimingSession s) {
  final line = s.lastLine;
  final pause = s.lastPause;
  final last = s.lastTake;
  if (line == null || (pause == null && last == null)) return null;
  final shown = pause ?? last!.durationSeconds;
  return Spoken(
    semanticLabel: pause != null
        ? 'Zapisano kwestię ${line.index}: pauza ${seconds(pause)}'
        : 'Zapisano kwestię ${line.index}: '
              '${seconds(last!.durationSeconds)} (+1 s pauzy)',
    child: Row(
      spacing: AppSpacing.xs,
      children: [
        const Icon(Icons.save_outlined, size: 16),
        Text('${line.index}'),
        Icon(pause != null ? Icons.hourglass_bottom : Icons.mic_none, size: 16),
        Text(seconds(shown)),
      ],
    ),
  );
}
