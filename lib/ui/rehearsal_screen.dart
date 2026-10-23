import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/session.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/cue_view.dart';
import 'package:sufler/ui/rehearsal_summary.dart';
import 'package:sufler/ui/services.dart';

/// The rehearsal itself: partner lines aloud, a countdown for mine.
class RehearsalScreen extends StatefulWidget {
  /// Creates the screen; the walk starts immediately.
  const new({
    required this.script,
    required this.cues,
    required this.title,
    required this.settings,
    required this.speed,
    required this.recordings,
    required this.resume,
    this.pack,
    super.key,
  });

  /// What is rehearsed and where to start; the reached position is saved
  /// back so the next start continues here.
  final ResumePoint resume;

  /// The script.
  final Script script;

  /// The walk.
  final List<Cue> cues;

  /// Section label for the app bar.
  final String title;

  /// Visibility, grading and loop settings.
  final AppSettings settings;

  /// Global speed (TTS rate).
  final double speed;

  /// Line index -> storage key of the actor's recording.
  final Map<int, String> recordings;

  /// Rendered voices, if loaded.
  final AudioPack? pack;

  @override
  State<RehearsalScreen> createState() => _RehearsalScreenState();
}

class _RehearsalScreenState extends State<RehearsalScreen> {
  RehearsalController? _ctl;
  int _saved = -1;

  Services get _svc => ServicesScope.of(context);
  String get _id => widget.script.id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctl != null) return;
    final svc = ServicesScope.of(context);
    final s = widget.settings;
    _ctl = RehearsalController(
      RehearsalSession(
        widget.cues,
        selfGrade: s.grades,
        loop: s.loop,
        cleanTarget: s.cleanTarget,
        startAt: widget.resume.position,
      ),
      PartnerPlayer(
        script: widget.script,
        speech: svc.speech,
        clips: svc.clips,
        pack: widget.pack,
        speed: widget.speed,
      ),
      capture: s.listen ? svc.capture : null,
    )..start();
    _ctl!.addListener(_savePosition);
    _savePosition();
  }

  /// Keeps the resume point at the cue reached (the start once finished).
  void _savePosition() {
    final s = _ctl!.session;
    final at = s.phase == Phase.finished ? 0 : s.position;
    if (at == _saved) return;
    _saved = at;
    unawaited(
      _svc.library.updatePrefs(
        _id,
        (p) => p.copyWith(resume: widget.resume.at(at)),
      ),
    );
  }

  void _grade(bool ok) {
    final ctl = _ctl!;
    final index = ctl.session.current?.line.index;
    if (index == null || ctl.session.phase != Phase.grade) return;
    ctl.grade(ok: ok);
    unawaited(_svc.library.updatePrefs(_id, (p) => p.graded(index, ok: ok)));
  }

  void _confirmSuggestion() {
    final s = _ctl!.suggestion;
    if (s != null) _grade(s);
  }

  void _adjust(double delta) {
    final ctl = _ctl!;
    final index = ctl.session.current!.line.index;
    final next = ctl.adjustPause(delta);
    unawaited(
      _svc.library.updatePrefs(
        _id,
        (p) => p.copyWith(lineSeconds: {...p.lineSeconds, index: next}),
      ),
    );
  }

  @override
  void dispose() {
    _ctl?.removeListener(_savePosition);
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _playRecording(int index) async {
    final key = widget.recordings[index];
    if (key == null) return;
    final wav = await _svc.library.loadRecording(key);
    if (wav != null) await _svc.clips.play(wav, 'audio/wav');
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl!;
    return PopScope(
      // Silence at once on leaving, not after the exit transition.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ctl.pause();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): ctl.done,
          const SingleActivator(LogicalKeyboardKey.enter): _confirmSuggestion,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: ListenableBuilder(
              listenable: ctl,
              builder: (context, _) => _body(ctl),
            ),
            bottomNavigationBar: ListenableBuilder(
              listenable: ctl,
              builder: (context, _) => _controls(ctl),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(RehearsalController ctl) {
    final session = ctl.session;
    final Widget content = session.phase == Phase.finished
        ? RehearsalSummary(session: session, onAgain: ctl.restart)
        : CueView(
            script: widget.script,
            controller: ctl,
            visibility: widget.settings.visibility,
            hasRecording: widget.recordings.containsKey,
            onPlayRecording: _playRecording,
            onGrade: _grade,
            onAdjust: _adjust,
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [_header(session), const Divider(), content],
        ),
      ),
    );
  }

  Widget _header(RehearsalSession s) {
    final parts = [
      'Przebieg ${s.pass}',
      if (s.phase != Phase.finished)
        'kwestia ${s.position + 1}/${s.cues.length}',
      if (s.loop) 'czyste z rzędu ${s.cleanStreak}/${s.cleanTarget}',
      if (s.history.isNotEmpty && s.phase != Phase.finished)
        'ostatni wynik ${s.history.last}',
    ];
    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _controls(RehearsalController ctl) {
    final over = ctl.session.phase == Phase.finished;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Wstecz',
              icon: const Icon(Icons.skip_previous),
              onPressed: ctl.back,
            ),
            IconButton.filledTonal(
              tooltip: ctl.paused ? 'Wznów' : 'Pauza',
              icon: Icon(ctl.paused ? Icons.play_arrow : Icons.pause),
              onPressed: over ? null : (ctl.paused ? ctl.resume : ctl.pause),
            ),
            IconButton(
              tooltip: 'Dalej',
              icon: const Icon(Icons.skip_next),
              onPressed: over ? null : ctl.skip,
            ),
          ],
        ),
      ),
    );
  }
}
