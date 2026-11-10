import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/run_take.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/rehearsal/timing_session.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/status_glyph.dart';
import 'package:sufler/ui/timing_prompts.dart';
import 'package:sufler/ui/timing_run_view.dart';

/// "Nagraj czasy": reads my [lines] one after another, hands-free. Each
/// line's pause becomes how long I took to say it (+1 s), with the
/// recording kept when the platform records audio. "Stop" ends it.
class TimingSessionScreen extends StatefulWidget {
  /// Creates the screen; the walk starts at once.
  const new({
    required this.scriptId,
    required this.title,
    required this.lines,
    this.runs = const [],
    super.key,
  });

  /// Script id in the library.
  final String scriptId;

  /// Section label.
  final String title;

  /// My lines to time, in order.
  final List<ScriptLine> lines;

  /// My runs (`findRuns`): each offered as one take, "Nagraj w całości".
  final List<LineRun> runs;

  @override
  State<TimingSessionScreen> createState() => _TimingSessionScreenState();
}

class _TimingSessionScreenState extends State<TimingSessionScreen> {
  TimingSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    final svc = ServicesScope.of(context);
    final session = _session = TimingSession(
      lines: widget.lines,
      capture: svc.capture,
      save: (line, take) => svc.library.saveTake(
        widget.scriptId,
        line.index,
        seconds: take.durationSeconds,
        audio: take.audio,
      ),
      // A tapped time is a manual pause and a pace sample; any recording
      // stays as it is.
      saveTime: (line, pause) => svc.library.updatePrefs(
        widget.scriptId,
        (p) => p.copyWith(
          lineSeconds: {...p.lineSeconds, line.index: pause},
          tapSeconds: {...p.tapSeconds, line.index: pause},
        ),
      ),
      whole: WholeRuns(
        runs: widget.runs,
        mic: RunMic(
          start: svc.recorder.start,
          stop: svc.recorder.stop,
          transcribe: svc.transcribe,
        ),
        hasRecording: (line) async =>
            (await svc.library.loadPrefs(widget.scriptId)).recordings
                .containsKey(line.index),
      ),
    );
    unawaited(session.run());
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    return Scaffold(
      appBar: AppBar(
        title: Icon(
          Icons.timelapse,
          semanticLabel: 'Nagraj czasy: ${widget.title}',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: _body(context, session),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, TimingSession s) {
    final theme = Theme.of(context).textTheme;
    final total = s.lines.length;
    if (s.state == TakeState.done) {
      return [
        Icon(
          Icons.check_circle_outline,
          size: 32,
          semanticLabel: 'Gotowe: zapisano ${s.saved} z $total',
        ),
        if (s.problem case final problem?)
          statusGlyph(context, problem, ok: false),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          key: const Key('close-btn'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, semanticLabel: 'Zamknij'),
        ),
      ];
    }
    final line = s.current!;
    return [
      Icon(
        Icons.flag_outlined,
        semanticLabel: 'Kwestia ${s.position + 1}/$total',
      ),
      LinearProgressIndicator(value: s.position / total),
      SwitchListTile(
        key: const Key('manual-walk'),
        contentPadding: EdgeInsets.zero,
        title: const Icon(
          Icons.mic_off,
          semanticLabel: 'Bez mikrofonu: stuknij po każdej kwestii',
        ),
        value: s.manualAll,
        onChanged: (on) => s.setManual(on: on),
      ),
      const SizedBox(height: AppSpacing.md),
      if (s.state case TakeState.run || TakeState.overwrite)
        ...runViews(context, s)
      else if (s.state == TakeState.manual)
        ...manualViews(context, s)
      else ...[
        const Icon(
          Icons.record_voice_over,
          semanticLabel: 'Przeczytaj na głos:',
        ),
        Text(line.text, style: theme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        ValueListenableBuilder<double>(
          valueListenable: _levelSource,
          builder: (context, level, _) => LinearProgressIndicator(
            key: const Key('level'),
            value: level,
            minHeight: AppSpacing.sm,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (s.state == TakeState.listening) ...[
        Icon(
          Icons.mic,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
          semanticLabel: 'Słucham… gdy skończysz mówić, przejdę dalej.',
        ),
        ?runOffer(s),
      ],
      if (s.runNote case final note?)
        statusGlyph(context, note, ok: !note.startsWith('Nie ')),
      ?savedView(s),
      if (s.state == TakeState.skipped) ...skippedViews(s),
      const SizedBox(height: AppSpacing.lg),
      FilledButton.tonalIcon(
        onPressed: () => unawaited(s.stop()),
        icon: const Icon(Icons.stop, semanticLabel: 'Stop'),
        label: const SizedBox.shrink(),
      ),
    ];
  }

  ValueListenable<double> get _levelSource =>
      ServicesScope.of(context).capture.level;
}
