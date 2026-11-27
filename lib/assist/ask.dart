import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/assist/pc_link.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/line_edits.dart';
import 'package:sufler/storage/pending_asks.dart';
import 'package:sufler/storage/prefs.dart';

/// Shown while a question waits for the PC.
const String offlineAskMessage = 'PC offline — wyślę, gdy będzie dostępny';

/// How often a question is re-sent after the PC came back and failed again.
const int askAttempts = 5;

/// One "Zapytaj Claude" request about [selection] in line [index]. It runs
/// on its own, not tied to the sheet that started it: while the PC is
/// offline it waits for [PcLink.back], and the answer is saved as a note on
/// the line whenever it arrives ([onSaved] gets the prefs then). A question
/// is stored under `asks/<id>` the moment it is asked and dropped once
/// answered or refused by the PC, so an app restart never loses it
/// (`RehearsalAssist.load` asks the stored ones again).
class Ask extends ChangeNotifier {
  /// Sends the question at once.
  new({
    required this.link,
    required this.library,
    required this.script,
    required this.index,
    required this.selection,
    this.onSaved,
    this.saved = false,
  }) {
    unawaited(_run());
  }

  /// The PC side.
  final PcLink link;

  /// Where the note is saved.
  final ScriptLibrary library;

  /// The script asked about.
  final Script script;

  /// The line asked about.
  final int index;

  /// The words asked about.
  final String selection;

  /// Already stored under `asks/<id>` (asked again after a restart).
  final bool saved;

  /// Called with the prefs once the note is saved.
  final ValueChanged<RehearsalPrefs>? onSaved;

  /// Waiting for the PC to come back.
  bool offline = false;

  /// The explanation, once it arrived.
  String? answer;

  /// Why it failed for good, if it did.
  String? error;

  void _state({bool offline = false, String? error}) {
    this.offline = offline;
    this.error = error;
    notifyListeners();
  }

  Future<void> _run() async {
    final pending = (index: index, selection: selection);
    final inFlight = library.asksInFlight(script.id)..add(pending);
    try {
      await _send(pending);
    } finally {
      inFlight.remove(pending);
    }
  }

  Future<void> _send(PendingAsk pending) async {
    if (!saved) await library.savePendingAsk(script.id, pending);
    for (var i = 0; i < askAttempts; i++) {
      if (link.online == false) {
        _state(offline: true);
        await link.back;
        _state();
      }
      try {
        final text = await link.assistant.explain(
          script: script,
          index: index,
          selection: selection,
        );
        final note = LineNote(about: selection, text: text);
        final prefs = await library.addNote(script.id, index, note);
        await library.dropPendingAsk(script.id, pending);
        answer = text;
        _state();
        onSaved?.call(prefs);
        return;
      } on Object catch (e) {
        // Online and still failing: the PC's own error, not a lost link.
        if (link.online ?? false) {
          await library.dropPendingAsk(script.id, pending);
          return _state(error: '$e');
        }
        link.lost();
      }
    }
    _state(error: 'PC nie odpowiada');
  }
}
