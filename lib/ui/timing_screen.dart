import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/line_timing_sheet.dart';
import 'package:sufler/ui/services.dart';

/// My lines with their pause length; tap one to override or record it.
class TimingScreen extends StatefulWidget {
  /// Opens the stored script [scriptId].
  const TimingScreen({required this.scriptId, super.key});

  /// Id of the script in the library.
  final String scriptId;

  @override
  State<TimingScreen> createState() => _TimingScreenState();
}

class _TimingScreenState extends State<TimingScreen> {
  Script? _script;
  RehearsalPrefs _prefs = const RehearsalPrefs();
  Map<int, double> _recorded = const {};

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
          seconds: _seconds(line),
        ),
      ),
    );
    await _load();
  }

  double _seconds(ScriptLine line) => pauseSeconds(
    index: line.index,
    text: line.text,
    speed: _prefs.speed,
    overrides: _prefs.lineSeconds,
    recordingSeconds: _recorded,
  );

  String _source(int index) {
    if (_prefs.lineSeconds.containsKey(index)) return 'ręcznie';
    if (_recorded.containsKey(index)) return 'z nagrania';
    return 'automatycznie';
  }

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
                    for (final l in lines)
                      ListTile(
                        leading: Text('${l.index}'),
                        title: Text(l.text),
                        subtitle: Text(
                          'Pauza ${seconds(_seconds(l))} · ${_source(l.index)}',
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
