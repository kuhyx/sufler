import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/assist/pc_link.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/line_edits.dart';

/// Shown on a corrected line still said by device TTS.
const String ttsUntilRendered = 'głos: syntezator do czasu wygenerowania';

/// Corrected lines of [script] that should have a voice clip but do not:
/// [pack] exists and lacks a clip for a spoken line in [edited].
Set<int> missingVoices(Script script, AudioPack? pack, Set<int> edited) => {
  if (pack != null)
    for (final i in edited)
      if (i < script.lines.length &&
          script.lines[i].isSpoken &&
          pack.clip(i) == null)
        i,
};

/// New voice clips for corrected lines, rendered by the PC: tried at once,
/// again whenever the PC comes back. [pending] lines play with device TTS
/// meanwhile; [onPack] gets the stored pack after each new clip.
class LineVoices extends ChangeNotifier {
  /// Starts rendering [pending] lines of [script].
  new({
    required this.link,
    required this.library,
    required this.script,
    required this.onPack,
    Set<int> pending = const {},
  }) {
    this.pending.addAll(pending);
    _sub = link.changes.listen((on) {
      if (on) _renderAll();
    });
    _renderAll();
  }

  void _renderAll() => pending.toList().forEach(_render);

  /// The PC side.
  final PcLink link;

  /// Where clips are stored.
  final ScriptLibrary library;

  /// A new clip is stored: the pack as it is now.
  final ValueChanged<AudioPack> onPack;

  /// The script as it is now (corrections applied).
  Script script;

  /// Lines waiting for a clip.
  final pending = <int>{};

  final _busy = <int>{};
  final _again = <int>{};
  StreamSubscription<bool>? _sub;
  bool _disposed = false;

  /// Line [index] of [now] was corrected: render its voice again.
  void request(Script now, int index) {
    script = now;
    pending.add(index);
    notifyListeners();
    _render(index);
  }

  void _render(int index) {
    if (_busy.contains(index)) {
      _again.add(index);
      return;
    }
    if (link.online == false || _disposed) return;
    _busy.add(index);
    unawaited(_attempt(index));
  }

  Future<void> _attempt(int index) async {
    final asked = script.lines[index];
    try {
      final clip = await link.assistant.renderLine(
        script: script,
        index: index,
      );
      final now = script.lines[index];
      // Corrected again meanwhile: that newer request renders it.
      final stale =
          now.text != asked.text || !listEquals(now.speakers, asked.speakers);
      if (clip == null || stale || _disposed) return;
      final at = script;
      final pack = await library.storeLineClip(at, index, clip);
      // Another line was corrected meanwhile (the pack is stamped anew):
      // render this one again for the script as it is now.
      if (pack == null && !identical(at, script)) _again.add(index);
      if (pack == null || _disposed) return;
      pending.remove(index);
      onPack(pack);
      notifyListeners();
    } on Object catch (e) {
      debugPrint('render of line $index failed: $e');
      if (!(link.online ?? false)) link.lost();
    } finally {
      _busy.remove(index);
      if (_again.remove(index)) _render(index);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
