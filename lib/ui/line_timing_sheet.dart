import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/services.dart';

/// Per-line pause: manual seconds, back to automatic, or "record me".
///
/// A new recording clears the manual override so its length (+1 s) takes
/// effect: the last thing the actor did wins.
class LineTimingSheet extends StatefulWidget {
  /// Creates the sheet.
  const LineTimingSheet({
    required this.scriptId,
    required this.line,
    required this.seconds,
    super.key,
  });

  /// Script id in the library.
  final String scriptId;

  /// The line.
  final ScriptLine line;

  /// Current effective pause.
  final double seconds;

  @override
  State<LineTimingSheet> createState() => _LineTimingSheetState();
}

class _LineTimingSheetState extends State<LineTimingSheet> {
  late final _field = TextEditingController(
    text: widget.seconds.toStringAsFixed(1),
  );
  bool _recording = false;
  bool _hasRecording = false;

  Services get _svc => ServicesScope.of(context);
  int get _index => widget.line.index;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_checkRecording());
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _checkRecording() async {
    final prefs = await _svc.library.loadPrefs(widget.scriptId);
    if (mounted) {
      setState(() => _hasRecording = prefs.recordings.containsKey(_index));
    }
  }

  Future<void> _setOverride(double? value) async {
    final lib = _svc.library;
    final prefs = await lib.loadPrefs(widget.scriptId);
    final map = {...prefs.lineSeconds}..remove(_index);
    if (value != null) map[_index] = value;
    await lib.savePrefs(widget.scriptId, prefs.copyWith(lineSeconds: map));
    if (mounted) Navigator.of(context).pop();
  }

  void _apply() {
    final v = double.tryParse(_field.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) {
      showError(context, 'Podaj liczbę sekund większą od zera');
      return;
    }
    unawaited(_setOverride(v));
  }

  Future<void> _toggleRecord() async {
    if (!_recording) {
      final ok = await _svc.recorder.start();
      if (!mounted) return;
      if (!ok) {
        showError(context, 'Brak dostępu do mikrofonu');
        return;
      }
      setState(() => _recording = true);
      return;
    }
    final wav = await _svc.recorder.stop();
    setState(() => _recording = false);
    if (wav == null) return;
    final lib = _svc.library;
    await lib.saveRecording(widget.scriptId, _index, wav);
    await _setOverride(null);
  }

  Future<void> _play() async {
    final prefs = await _svc.library.loadPrefs(widget.scriptId);
    final key = prefs.recordings[_index];
    final wav = key == null ? null : await _svc.library.loadRecording(key);
    if (wav != null) await _svc.clips.play(wav, 'audio/wav');
  }

  Future<void> _deleteRecording() async {
    await _svc.library.deleteRecording(widget.scriptId, _index);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.line.text, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text('Teraz: ${seconds(widget.seconds)}'),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('seconds'),
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pauza (sekundy)'),
          onSubmitted: (_) => _apply(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(onPressed: _apply, child: const Text('Ustaw pauzę')),
            OutlinedButton(
              onPressed: () => _setOverride(null),
              child: const Text('Automatycznie'),
            ),
          ],
        ),
        const Divider(height: AppSpacing.xl),
        FilledButton.tonalIcon(
          onPressed: _toggleRecord,
          icon: Icon(_recording ? Icons.stop : Icons.mic),
          label: Text(_recording ? 'Zatrzymaj nagrywanie' : 'Nagraj mnie'),
        ),
        if (_hasRecording)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Odtwórz nagranie'),
              ),
              TextButton.icon(
                onPressed: _deleteRecording,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Usuń nagranie'),
              ),
            ],
          ),
      ],
    ),
  );
}
