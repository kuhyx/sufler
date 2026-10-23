// coverage:ignore-file
// Platform glue over audioplayers; needs a real audio output.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:sufler/rehearsal/partner_player.dart';

/// Plays in-memory clips (pack Ogg/Opus, own WAV recordings).
class AudioClips implements ClipPlayer {
  final AudioPlayer _player = AudioPlayer();
  Completer<void>? _playing;

  @override
  Future<void> play(Uint8List bytes, String mimeType) async {
    await stop();
    final done = _playing = Completer<void>();
    final sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.play(BytesSource(bytes, mimeType: mimeType));
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> stop() async {
    final p = _playing;
    if (p != null && !p.isCompleted) p.complete();
    _playing = null;
    await _player.stop();
  }
}
