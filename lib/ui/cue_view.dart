import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/session.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';

/// The current cue (partner line, my countdown, or my self-grade), with the
/// previous line above it for context. In "reveal after pause" mode the
/// previous panel is where my just-said line appears.
class CueView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.script,
    required this.controller,
    required this.visibility,
    required this.hasRecording,
    required this.onPlayRecording,
    super.key,
  });

  /// The script.
  final Script script;

  /// The running rehearsal.
  final RehearsalController controller;

  /// Own-line text visibility.
  final TextVisibility visibility;

  /// Whether line index has an own recording.
  final bool Function(int index) hasRecording;

  /// Play the own recording of a line.
  final void Function(int index) onPlayRecording;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    final cue = s.current!;
    final prev = s.position > 0 ? s.cues[s.position - 1] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prev != null) _previous(context, prev),
        const SizedBox(height: AppSpacing.lg),
        switch (s.phase) {
          Phase.partner => _partner(context, cue),
          Phase.mine => _mine(context, cue),
          _ => _grade(context, cue),
        },
      ],
    );
  }

  Widget _previous(BuildContext context, Cue prev) {
    final hidden = prev.mine && visibility == TextVisibility.hide;
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      children: [
        Expanded(
          child: Text(
            hidden ? '(twoja kwestia)' : prev.line.text,
            style: style,
          ),
        ),
        if (prev.mine && hasRecording(prev.line.index)) _playButton(prev),
      ],
    );
  }

  Widget _playButton(Cue cue) => IconButton(
    tooltip: 'Odtwórz moje nagranie',
    icon: const Icon(Icons.hearing),
    onPressed: () => onPlayRecording(cue.line.index),
  );

  Widget _label(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);

  Widget _text(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);

  Widget _partner(BuildContext context, Cue cue) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, speakerNames(script, cue.line)),
      const SizedBox(height: AppSpacing.sm),
      _text(context, cue.line.text),
      for (final d in cue.line.directions)
        Text(d, style: const TextStyle(fontStyle: FontStyle.italic)),
    ],
  );

  Widget _mine(BuildContext context, Cue cue) {
    final left = controller.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'Twoja kwestia'),
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
          _text(context, cue.line.text)
        else
          _text(context, '…'),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: controller.done,
          icon: const Icon(Icons.check),
          label: const Text('Gotowe'),
        ),
        Text(
          'albo spacja',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _grade(BuildContext context, Cue cue) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(context, 'Jak poszło?'),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          Expanded(
            child: _text(
              context,
              visibility == TextVisibility.hide ? '…' : cue.line.text,
            ),
          ),
          if (hasRecording(cue.line.index)) _playButton(cue),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => controller.grade(ok: false),
              icon: const Icon(Icons.close),
              label: const Text('Źle'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => controller.grade(ok: true),
              icon: const Icon(Icons.check),
              label: const Text('Dobrze'),
            ),
          ),
        ],
      ),
    ],
  );
}
