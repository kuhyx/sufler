import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';

/// My own line: countdown, then my text or a from-memory glyph, and done.
class MineView extends StatelessWidget {
  /// My [cue] in the running [controller].
  const new({
    required this.controller,
    required this.cue,
    required this.visibility,
    required this.textView,
    super.key,
  });

  /// The running rehearsal.
  final RehearsalController controller;

  /// My cue.
  final Cue cue;

  /// Own-line text visibility.
  final TextVisibility visibility;

  /// My line's text, long-press lookable.
  final Widget Function() textView;

  @override
  Widget build(BuildContext context) {
    final left = controller.remaining;
    final listening = controller.capture != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.primary,
          semanticLabel: 'Twoja kwestia',
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          seconds(left),
          key: const Key('countdown'),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        LinearProgressIndicator(
          value: cue.seconds <= 0 ? 0 : (left / cue.seconds).clamp(0, 1),
        ),
        const SizedBox(height: AppSpacing.md),
        if (visibility == TextVisibility.show)
          textView()
        else
          Row(
            key: const Key('from-memory'),
            children: [
              const Icon(
                Icons.psychology_outlined,
                size: 32,
                semanticLabel: 'Mów z pamięci…',
              ),
              if (listening)
                const Icon(Icons.mic, size: 32, semanticLabel: 'słucham'),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: controller.done,
          icon: const Icon(Icons.check, semanticLabel: 'Gotowe'),
          label: const SizedBox.shrink(),
        ),
        Icon(
          Icons.space_bar,
          color: Theme.of(context).colorScheme.outline,
          semanticLabel: 'albo spacja',
        ),
      ],
    );
  }
}
