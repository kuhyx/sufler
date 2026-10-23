import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/pace.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/line_timing_sheet.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/timing_session_screen.dart';

/// My lines with their pause length; tap one to override or record it.
class TimingScreen extends StatefulWidget {
  /// Opens the stored script [scriptId].
  const new({required this.scriptId, super.key});

  /// Id of the script in the library.
  final String scriptId;

  @override
  State<TimingScreen> createState() => _TimingScreenState();
}

class _TimingScreenState extends State<TimingScreen> {
  Script? _script;
  RehearsalPrefs _prefs = const RehearsalPrefs();
  Map<int, double> _recorded = const {};

  /// His pace, recomputed on every load (recordings may have changed).
  double? _pace;

  Services get _svc => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_script == null) unawaited(_load());
  }

  Future<void> _load() async {
    final lib = _svc.library;
    final script = await lib.loadScript(widget.scriptId);
    final prefs = await lib.loadPrefs(widget.scriptId);
    final recorded = await lib.recordingSeconds(prefs);
    if (!mounted) return;
    setState(() {
      _script = script;
      _prefs = prefs;
      _recorded = recorded;
      _pace = script == null ? null : secondsPerSyllable(script, recorded);
    });
  }

  Future<void> _open(ScriptLine line) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ServicesScope(
        services: _svc,
        child: LineTimingSheet(
          scriptId: widget.scriptId,
          line: line,
          seconds: _pause(line).seconds,
          estimated: _pause(line).source == PauseSource.estimate,
        ),
      ),
    );
    await _load();
  }

  Future<void> _recordAll(List<ScriptLine> lines) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimingSessionScreen(
          scriptId: widget.scriptId,
          title: 'wszystkie',
          lines: lines,
        ),
      ),
    );
    await _load();
  }

  ({double seconds, PauseSource source}) _pause(ScriptLine line) =>
      resolvePause(
        index: line.index,
        text: line.text,
        speed: _prefs.speed,
        overrides: _prefs.lineSeconds,
        recordingSeconds: _recorded,
        pace: _pace,
      );

  static String _source(PauseSource s) => switch (s) {
    PauseSource.manual => 'ręcznie',
    PauseSource.recording => 'z nagrania',
    PauseSource.estimate => 'szacowane',
    PauseSource.formula => 'automatycznie',
  };

  @override
  Widget build(BuildContext context) {
    final s = _script;
    final lines = s == null
        ? const <ScriptLine>[]
        : [
            for (final l in s.lines)
              if (l.isSpoken &&
                  (_prefs.roles.isEmpty || isMine(l, _prefs.roles)))
                l,
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('Czasy i nagrania')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    Text(
                      _prefs.roles.isEmpty
                          ? 'Nie wybrano ról: pokazuję wszystkie kwestie.'
                          : 'Twoje kwestie. Stuknij, by zmienić pauzę.',
                    ),
                    if (_prefs.roles.isNotEmpty && lines.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: FilledButton.icon(
                          onPressed: () => _recordAll(lines),
                          icon: const Icon(Icons.mic),
                          label: const Text('Nagraj czasy'),
                        ),
                      ),
                    for (final l in lines)
                      ListTile(
                        leading: Text('${l.index}'),
                        title: Text(l.text),
                        subtitle: Text(
                          'Pauza ${seconds(_pause(l).seconds)} · '
                          '${_source(_pause(l).source)}',
                        ),
                        trailing: _recorded.containsKey(l.index)
                            ? const Icon(Icons.mic)
                            : null,
                        onTap: () => _open(l),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
