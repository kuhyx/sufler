import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/pace.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/correction_screen.dart';
import 'package:sufler/ui/line_picker_screen.dart';
import 'package:sufler/ui/parse_refresh.dart';
import 'package:sufler/ui/rehearsal_screen.dart';
import 'package:sufler/ui/roles_screen.dart';
import 'package:sufler/ui/script_tabs.dart';
import 'package:sufler/ui/sections_tab.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/timing_screen.dart';
import 'package:sufler/ui/timing_session_screen.dart';

/// One script: learn (scenes, songs), rehearsal settings and tools as
/// tabs; roles on their own screen ("Moje role").
class ScriptScreen extends StatefulWidget {
  /// Opens the stored script [scriptId].
  const new({required this.scriptId, super.key});

  /// Id of the script in the library.
  final String scriptId;

  @override
  State<ScriptScreen> createState() => _ScriptScreenState();
}

class _ScriptScreenState extends State<ScriptScreen> {
  Script? _script;
  RehearsalPrefs _prefs = const RehearsalPrefs();
  AppSettings _settings = const AppSettings();
  AudioPack? _pack;
  bool _canRender = false;
  bool _loaded = false;
  bool _packWarned = false;
  bool _needsSource = false;

  Services get _svc => ServicesScope.of(context);
  String get _id => widget.scriptId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_firstLoad());
  }

  Future<void> _firstLoad() async {
    String? note;
    try {
      note = await refreshStaleParse(_svc, _id);
    } on Object catch (e) {
      debugPrint('re-parse of $_id failed: $e');
    }
    await _load();
    if (note != null && mounted) showToast(context, note);
    await _svc.library.rememberScript(_id);
    // First visit with no roles: show the roles screen once.
    if (!mounted || _prefs.roles.isNotEmpty || _prefs.rolesAsked) return;
    await _svc.library.updatePrefs(_id, (p) => p.copyWith(rolesAsked: true));
    await _push(RolesScreen(scriptId: _id));
  }

  Future<void> _load() async {
    final lib = _svc.library;
    final script = await lib.loadScript(_id);
    final prefs = await lib.loadPrefs(_id);
    final settings = await lib.loadSettings();
    final stored = await lib.loadPack(_id);
    final checked = stored == null || script == null
        ? null
        : checkPack(script, stored);
    final pack = checked?.pack;
    final canRender = await _svc.renderAvailable();
    final needsSource = await needsSourceFile(_svc, _id);
    if (!mounted) return;
    if (pack == null && checked != null && !_packWarned) {
      _packWarned = true;
      showError(context, checked.message!);
    }
    setState(() {
      _script = script;
      _prefs = prefs;
      _settings = settings;
      _pack = pack;
      _canRender = canRender;
      _needsSource = needsSource;
    });
  }

  Future<void> _savePrefs(
    RehearsalPrefs Function(RehearsalPrefs) change,
  ) async {
    final next = await _svc.library.updatePrefs(_id, change);
    if (mounted) setState(() => _prefs = next);
  }

  Future<void> _saveSettings(AppSettings s) async {
    setState(() => _settings = s);
    await _svc.library.saveSettings(s);
  }

  Future<void> _start(
    LineRange range,
    String label, {
    bool missedOnly = false,
    ResumePoint? from,
  }) async {
    final script = _script!;
    if (_prefs.roles.isEmpty) {
      showError(context, 'Wybierz co najmniej jedną rolę');
      return;
    }
    final recorded = await _svc.library.recordingSeconds(_prefs);
    final plain = buildCues(
      script,
      _prefs.roles,
      range,
      speed: _prefs.speed,
      overrides: _prefs.lineSeconds,
      recordingSeconds: recorded,
      pace: secondsPerSyllable(script, recorded, tapSeconds: _prefs.tapSeconds),
    );
    final (:cues, :start) = rehearsalWalk(
      plain,
      runs: _settings.wholeRuns ? rehearsalRuns(script, _prefs.roles) : null,
      missed: missedOnly ? _prefs.missed : null,
      line: from?.line,
      position: from?.position ?? 0,
    );
    if (!mounted) return;
    if (cues.isEmpty) {
      showError(context, 'Nie ma tu kwestii do powtórki');
      return;
    }
    final resume = ResumePoint(
      label: label,
      start: range.start,
      end: range.end,
      position: start,
      missedOnly: missedOnly,
    );
    // The rehearsal screen saves [resume] (and every position reached).
    await _push(
      RehearsalScreen(
        script: script,
        cues: cues,
        title: label,
        settings: _settings,
        speed: _prefs.speed,
        pack: _pack,
        recordings: _prefs.recordings,
        resume: resume,
      ),
    );
  }

  void _resume(ResumePoint r) => unawaited(
    _start(
      LineRange(r.start, r.end),
      r.label,
      missedOnly: r.missedOnly,
      from: r,
    ),
  );

  void _record(LineRange range, String label) => unawaited(
    _push(
      TimingSessionScreen(
        scriptId: _id,
        title: label,
        lines: ownLines(_script!, _prefs, range),
        runs: findRuns(_script!, _prefs.roles),
      ),
    ),
  );

  Future<void> _pick(PickMode mode) async {
    final range = await Navigator.of(context).push(
      MaterialPageRoute<LineRange>(
        builder: (_) => LinePickerScreen(script: _script!, mode: mode),
      ),
    );
    if (range == null) return;
    await _start(range, 'Kwestie ${range.start}–${range.end}');
  }

  Future<void> _refreshParse() async {
    try {
      final note = await refreshFromFile(_svc, _id);
      if (note == null) return;
      await _load();
      if (mounted) showToast(context, note);
    } on Object catch (e) {
      final why = e is FormatException ? e.message : '$e';
      if (mounted) showError(context, 'Nie odświeżono parsowania: $why');
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final script = _script;
    if (script == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ScriptTabs(
      script: script,
      prefs: _prefs,
      settings: _settings,
      pack: _pack,
      canRender: _canRender,
      onRoles: () => _push(RolesScreen(scriptId: _id)),
      onStart: _start,
      onMissed: () => _start(
        LineRange(0, script.lines.length - 1),
        'Tylko nieumiane',
        missedOnly: true,
      ),
      onResume: _resume,
      onRecord: _record,
      onPick: _pick,
      onSpeed: (s) => _savePrefs((p) => p.copyWith(speed: s)),
      onSettings: _saveSettings,
      onPack: (p) => setState(() => _pack = p),
      onCorrect: () => _push(CorrectionScreen(scriptId: script.id)),
      onTimings: () => _push(TimingScreen(scriptId: script.id)),
      onRefreshParse: _needsSource ? _refreshParse : null,
    );
  }
}
