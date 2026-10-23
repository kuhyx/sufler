import 'dart:typed_data';

import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/timing.dart';
import 'package:sufler/rehearsal/voices.dart';

/// The device could not say a line, e.g. Chromium on Linux without
/// speech-dispatcher has no voices and fails every utterance.
class SpeechFailure implements Exception {
  /// Creates the failure with the engine's [reason].
  const new(this.reason);

  /// Engine error, e.g. `synthesis-failed`.
  final String reason;

  @override
  String toString() => 'SpeechFailure: $reason';
}

/// Device text-to-speech in Polish. Completes when the utterance ends.
abstract interface class Speech {
  /// Says [text] with [voice] at global [speed]. Throws [SpeechFailure] when
  /// the engine reports an error, rather than never completing.
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
      try {
        await speech.speak(line.text, voiceFor(script, line), speed);
      } on SpeechFailure {
        // No voice: keep the partner's text on screen for about as long as
        // saying it would take, so the cue can be read instead of heard.
        final hold = defaultPauseSeconds(line.text, speed: speed);
        await Future<void>.delayed(
          Duration(milliseconds: (hold * 1000).round()),
        );
      }
    }
  }

  @override
  Future<void> stop() async {
    await speech.stop();
    await clips.stop();
  }
}
