import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sufler/assist/ask.dart';
import 'package:sufler/assist/line_voices.dart';
import 'package:sufler/assist/pc_link.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/storage/line_edits.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/line_text_dialog.dart';
import 'package:sufler/ui/lookup_sheet.dart';
import 'package:sufler/ui/lookup_text.dart';
import 'package:sufler/ui/notes_view.dart';
import 'package:sufler/ui/services.dart';

/// Corrections, lookups and notes during a rehearsal. A correction goes
/// through the correction log ([LineEdits.correctLine]) and into the
/// running walk at once; a corrected line that had a voice clip is
/// rendered again by the PC ([LineVoices]), device TTS until then.
class RehearsalAssist extends ChangeNotifier {
  /// Works on the rehearsal driven by [controller] and voiced by [player].
  new({
    required this.services,
    required this.script,
    required this.controller,
    required this.player,
  });

  /// App services.
  final Services services;

  /// The running rehearsal.
  final RehearsalController controller;

  /// Partner voices (its pack and script follow corrections).
  final PartnerPlayer player;

  /// The script as it is now.
  Script script;

  /// Lines corrected by hand ("zmieniono").
  Set<int> edited = const {};

  /// The assistant's notes per line.
  Map<int, List<LineNote>> notes = const {};

  late final PcLink _link = PcLink.of(services.assistant);
  LineVoices? _voices;
  bool _disposed = false;

  /// Corrected lines still said by device TTS.
  Set<int> get ttsLines => _voices?.pending ?? const {};

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Reads corrections and notes; renders voices still missing.
  Future<void> load() async {
    final lib = services.library;
    edited = await lib.editedLines(script.id);
    notes = (await lib.loadPrefs(script.id)).notes;
    if (_disposed) return;
    _voices = LineVoices(
      link: _link,
      library: lib,
      script: script,
      onPack: (p) => player.pack = p,
      pending: missingVoices(script, player.pack, edited),
    )..addListener(_changed);
    _changed();
  }

  /// Pauses the walk during [body] (a dialog or sheet), then continues.
  Future<T?> _paused<T>(Future<T?> Function() body) async {
    final was = controller.paused;
    controller.pause();
    try {
      return await body();
    } finally {
      if (!was && !_disposed) controller.resume();
    }
  }

  /// ✎: corrects the text and speakers of [line].
  Future<void> edit(BuildContext context, ScriptLine line) => _paused(() async {
    final i = line.index;
    final e = await showDialog<LineTextEdit>(
      context: context,
      builder: (_) => LineTextDialog(script: script, line: script.lines[i]),
    );
    final now = script.lines[i];
    if (e == null) return;
    final text = e.text == now.text ? null : e.text;
    final same = listEquals(e.speakers, now.speakers);
    if (text == null && same) return;
    final hadClip = player.pack?.clip(i) != null;
    final r = await services.library.correctLine(
      script,
      i,
      text: text,
      speakers: same ? null : e.speakers,
    );
    script = player.script = r.script;
    if (player.pack != null) player.pack = r.pack;
    controller.session.replaceLine(r.script.lines[i]);
    edited = {...edited, i};
    _voices?.script = r.script;
    if (hadClip) _voices?.request(r.script, i);
    _changed();
  });

  /// The line of [cue] at [offset] of its text (lines joined by `\n`).
  static ScriptLine lineAt(Cue cue, int offset) {
    var start = 0;
    for (final l in cue.lines) {
      start += l.text.length + 1;
      if (offset < start) return l;
    }
    return cue.lines.last;
  }

  /// A long-pressed word of [cue]: the lookup sheet.
  void lookup(BuildContext context, Cue cue, LookupPick pick) {
    final line = lineAt(cue, pick.offset);
    Ask ask(String selection) => Ask(
      link: _link,
      library: services.library,
      script: script,
      index: line.index,
      selection: selection,
      onSaved: (p) {
        notes = p.notes;
        _changed();
      },
    );
    unawaited(
      _paused(
        () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) =>
              LookupSheet(pick: pick, openLink: services.openLink, ask: ask),
        ),
      ),
    );
  }

  /// Number of notes on [cue]'s lines.
  int noteCount(Cue cue) =>
      cue.lines.fold(0, (n, l) => n + (notes[l.index]?.length ?? 0));

  /// 💡: the notes of [cue]'s lines.
  void showCueNotes(BuildContext context, Cue cue) => unawaited(
    _paused(
      () => showNotes(context, 'Notatki', {
        for (final l in cue.lines) script.lines[l.index]: ?notes[l.index],
      }),
    ),
  );

  @override
  void dispose() {
    _disposed = true;
    _voices?.dispose();
    super.dispose();
  }
}
