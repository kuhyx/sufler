import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/correction_screen.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/line_picker_screen.dart';
import 'package:sufler/ui/rehearsal_screen.dart';
import 'package:sufler/ui/roles_card.dart';
import 'package:sufler/ui/sections_card.dart';
import 'package:sufler/ui/services.dart';
import 'package:sufler/ui/settings_card.dart';
import 'package:sufler/ui/timing_screen.dart';
import 'package:sufler/ui/tools_card.dart';

/// One script: pick roles and a section, tune the rehearsal, tools.
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

  Services get _svc => ServicesScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final lib = _svc.library;
    final script = await lib.loadScript(widget.scriptId);
    final prefs = await lib.loadPrefs(widget.scriptId);
    final settings = await lib.loadSettings();
    final pack = await lib.loadPack(widget.scriptId);
    final canRender = await _svc.renderAvailable();
    if (!mounted) return;
    setState(() {
      _script = script;
      _prefs = prefs;
      _settings = settings;
      _pack = pack;
      _canRender = canRender;
    });
  }

  Future<void> _savePrefs(RehearsalPrefs p) async {
    setState(() => _prefs = p);
    await _svc.library.savePrefs(widget.scriptId, p);
  }

  Future<void> _saveSettings(AppSettings s) async {
    setState(() => _settings = s);
    await _svc.library.saveSettings(s);
  }

  Future<void> _start(LineRange range, String label) async {
    final script = _script!;
    if (_prefs.roles.isEmpty) {
      showError(context, 'Wybierz co najmniej jedną rolę');
      return;
    }
    final recorded = await _svc.library.recordingSeconds(_prefs);
    final cues = buildCues(
      script,
      _prefs.roles,
      range,
      speed: _prefs.speed,
      overrides: _prefs.lineSeconds,
      recordingSeconds: recorded,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RehearsalScreen(
          script: script,
          cues: cues,
          title: label,
          settings: _settings,
          speed: _prefs.speed,
          pack: _pack,
          recordings: _prefs.recordings,
        ),
      ),
    );
  }

  Future<void> _pick(PickMode mode) async {
    final range = await Navigator.of(context).push(
      MaterialPageRoute<LineRange>(
        builder: (_) => LinePickerScreen(script: _script!, mode: mode),
      ),
    );
    if (range == null) return;
    await _start(range, 'Kwestie ${range.start}–${range.end}');
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
    final left = <Widget>[
      RolesCard(
        script: script,
        selected: _prefs.roles,
        onChanged: (r) => _savePrefs(_prefs.copyWith(roles: r)),
      ),
      SettingsCard(
        speed: _prefs.speed,
        settings: _settings,
        onSpeed: (s) => _savePrefs(_prefs.copyWith(speed: s)),
        onSettings: _saveSettings,
      ),
      ToolsCard(
        script: script,
        roles: _prefs.roles,
        pack: _pack,
        canRender: _canRender,
        onPack: (p) => setState(() => _pack = p),
        onCorrect: () => _push(CorrectionScreen(scriptId: script.id)),
        onTimings: () => _push(TimingScreen(scriptId: script.id)),
      ),
    ];
    final sections = SectionsCard(
      script: script,
      onStart: _start,
      onPick: _pick,
    );
    return Scaffold(
      appBar: AppBar(title: Text(script.title)),
      body: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= wideLayout
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _column(left)),
                  Expanded(child: _column([sections])),
                ],
              )
            : _column([left.first, sections, ...left.skip(1)]),
      ),
    );
  }

  Widget _column(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      for (final c in children) ...[c, const SizedBox(height: AppSpacing.lg)],
    ],
  );
}
