import 'dart:typed_data';

import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/voices.dart';

/// Device text-to-speech in Polish. Completes when the utterance ends.
abstract interface class Speech {
  /// Says [text] with [voice] at global [speed].
  Future<void> speak(String text, Voice voice, double speed);

  /// Interrupts speech.
  Future<void> stop();
}

/// Plays an in-memory audio clip. Completes when playback ends.
abstract interface class ClipPlayer {
  /// Plays [bytes] of type [mimeType].
  Future<void> play(Uint8List bytes, String mimeType);

  /// Interrupts playback.
  Future<void> stop();
}

/// Partner lines: the rendered clip from [pack] when it has one, otherwise
/// device TTS with a per-character voice.
class PartnerPlayer implements LinePlayer {
  /// Creates a player for [script].
  new({
    required this.script,
    required this.speech,
    required this.clips,
    this.pack,
    this.speed = 1,
  });

  /// Script being rehearsed (for voice assignment).
  final Script script;

  /// TTS fallback.
  final Speech speech;

  /// Clip output.
  final ClipPlayer clips;

  /// Rendered voices, if loaded.
  final AudioPack? pack;

  /// Global speed multiplier, applied to TTS rate.
  final double speed;

  @override
  Future<void> play(ScriptLine line) async {
    final clip = pack?.clip(line.index);
    if (clip != null) {
      await clips.play(clip, 'audio/ogg');
    } else {
      await speech.speak(line.text, voiceFor(script, line), speed);
    }
  }

  @override
  Future<void> stop() async {
    await speech.stop();
    await clips.stop();
  }
}
