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
  const RehearsalScreen({
    required this.script,
    required this.cues,
    required this.title,
    required this.settings,
    required this.speed,
    required this.recordings,
    this.pack,
    super.key,
  });

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctl != null) return;
    final svc = ServicesScope.of(context);
    final s = widget.settings;
    _ctl = RehearsalController(
      RehearsalSession(
        widget.cues,
        selfGrade: s.selfGrade,
        loop: s.loop,
        cleanTarget: s.cleanTarget,
      ),
      PartnerPlayer(
        script: widget.script,
        speech: svc.speech,
        clips: svc.clips,
        pack: widget.pack,
        speed: widget.speed,
      ),
    )..start();
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _playRecording(int index) async {
    final key = widget.recordings[index];
    if (key == null) return;
    final svc = ServicesScope.of(context);
    final wav = await svc.library.loadRecording(key);
    if (wav != null) await svc.clips.play(wav, 'audio/wav');
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
        bindings: {const SingleActivator(LogicalKeyboardKey.space): ctl.done},
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
