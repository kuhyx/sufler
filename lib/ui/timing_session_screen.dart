import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/timing_session.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/services.dart';

/// "Nagraj czasy": reads my [lines] one after another, hands-free. Each
/// line's pause becomes how long I took to say it (+1 s), with the
/// recording kept when the platform records audio. "Stop" ends it.
class TimingSessionScreen extends StatefulWidget {
  /// Creates the screen; the walk starts at once.
  const new({
    required this.scriptId,
    required this.title,
    required this.lines,
    super.key,
  });

  /// Script id in the library.
  final String scriptId;

  /// Section label.
  final String title;

  /// My lines to time, in order.
  final List<ScriptLine> lines;

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
      appBar: AppBar(title: Text('Nagraj czasy: ${widget.title}')),
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
    final last = s.lastTake;
    final saved = s.lastLine == null || last == null
        ? null
        : 'Zapisano kwestię ${s.lastLine!.index}: '
              '${seconds(last.durationSeconds)} (+1 s pauzy)';
    if (s.state == TakeState.done) {
      return [
        Text('Gotowe: zapisano ${s.saved} z $total', style: theme.titleLarge),
        if (s.problem != null) Text(s.problem!),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zamknij'),
        ),
      ];
    }
    final line = s.current!;
    return [
      Text('Kwestia ${s.position + 1}/$total', style: theme.labelLarge),
      LinearProgressIndicator(value: s.position / total),
      const SizedBox(height: AppSpacing.lg),
      Text('Przeczytaj na głos:', style: theme.bodySmall),
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
      if (s.state == TakeState.listening)
        const Text('Słucham… gdy skończysz mówić, przejdę dalej.'),
      if (saved != null) Text(saved, style: theme.bodySmall),
      if (s.state == TakeState.skipped) ..._skipped(s),
      const SizedBox(height: AppSpacing.lg),
      FilledButton.tonalIcon(
        onPressed: () => unawaited(s.stop()),
        icon: const Icon(Icons.stop),
        label: const Text('Stop'),
      ),
    ];
  }

  ValueListenable<double> get _levelSource =>
      ServicesScope.of(context).capture.level;

  List<Widget> _skipped(TimingSession s) {
    final other = s.lines[s.skipTo!];
    return [
      const SizedBox(height: AppSpacing.md),
      Text(
        'To brzmi jak kolejna kwestia (${s.skipTo! + 1}/${s.lines.length}): '
        '„${other.text}”',
        key: const Key('skip-warning'),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        children: [
          FilledButton(
            onPressed: s.accept,
            child: const Text('Tak, zapisz tam'),
          ),
          OutlinedButton(onPressed: s.redo, child: const Text('Powtórz tę')),
        ],
      ),
    ];
  }
}
