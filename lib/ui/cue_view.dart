import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/session.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/grade_view.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/pause_control.dart';

/// The current cue (partner line, my countdown, or my self-grade), with the
/// previous line above it for context. My own text stays hidden while I
/// say it unless the read-through mode shows it. After a ✗ the line is
/// hidden again and its prompt (the cue before it) replayed.
class CueView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.script,
    required this.controller,
    required this.visibility,
    required this.hasRecording,
    required this.onPlayRecording,
    required this.onGrade,
    required this.onAdjust,
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

  /// The actor's grade of the line just said.
  final ValueChanged<bool> onGrade;

  /// −/+ on the current own line's pause.
  final ValueChanged<double> onAdjust;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    final cue = s.current!;
    final prompt = s.phase == Phase.prompt ? s.prompt : null;
    final prev = s.position > 0 && prompt == null
        ? s.cues[s.position - 1]
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prev != null) _previous(context, prev),
        const SizedBox(height: AppSpacing.lg),
        if (s.retry) ...[
          Text(
            'Jeszcze raz — aż będzie dobrze',
            key: const Key('retry'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        switch (s.phase) {
          Phase.partner => _partner(context, cue),
          Phase.prompt => _partner(context, prompt!, hide: prompt.mine),
          Phase.mine => _mine(context, cue),
          _ => GradeView(
            cue: cue,
            visibility: visibility,
            heard: controller.heard,
            suggestion: controller.suggestion,
            onGrade: onGrade,
            trailing: hasRecording(cue.line.index) ? _playButton(cue) : null,
          ),
        },
        if (cue.mine) ...[
          const SizedBox(height: AppSpacing.md),
          PauseControl(
            length: cue.seconds,
            estimated: cue.estimated,
            onAdjust: onAdjust,
          ),
        ],
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

  /// A partner line, or a replayed prompt ([hide]: it is mine, shown only
  /// when the visibility allows).
  Widget _partner(BuildContext context, Cue cue, {bool hide = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(context, speakerNames(script, cue.line)),
      const SizedBox(height: AppSpacing.sm),
      _text(
        context,
        hide && visibility == TextVisibility.hide
            ? '(twoja kwestia)'
            : cue.line.text,
      ),
      for (final d in cue.line.directions)
        Text(d, style: const TextStyle(fontStyle: FontStyle.italic)),
    ],
  );

  Widget _mine(BuildContext context, Cue cue) {
    final left = controller.remaining;
    final listening = controller.capture != null;
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
          _text(
            context,
            listening ? 'Mów z pamięci… słucham' : 'Mów z pamięci…',
          ),
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
}
