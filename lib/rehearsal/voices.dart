import 'package:flutter/foundation.dart';
import 'package:sufler/model/script.dart';

/// Device-TTS settings for one character, so partner voices sound distinct.
@immutable
class Voice {
  /// Creates a voice.
  const Voice(this.pitch, this.rate);

  /// TTS pitch (1.0 = default).
  final double pitch;

  /// TTS speech rate at speed 1 (flutter_tts scale, 0.5 = normal).
  final double rate;

  /// Rate at global [speed], kept within the TTS range.
  double rateAt(double speed) => (rate * speed).clamp(0.1, 1.0);

  @override
  bool operator ==(Object other) =>
      other is Voice && other.pitch == pitch && other.rate == rate;

  @override
  int get hashCode => Object.hash(pitch, rate);

  @override
  String toString() => 'Voice(pitch $pitch, rate $rate)';
}

/// Neutral voice for unattributed lines (chorus lyrics).
const narratorVoice = Voice(1, 0.5);

const _pitches = [0.8, 1.25, 0.95, 1.4, 0.7, 1.1];
const _rates = [0.48, 0.52, 0.45, 0.55, 0.5];

/// Voice of [line]'s first speaker, stable per cast position.
Voice voiceFor(Script script, ScriptLine line) {
  if (line.speakers.isEmpty) return narratorVoice;
  final i = script.characters.indexWhere((c) => c.id == line.speakers.first);
  if (i < 0) return narratorVoice;
  return Voice(_pitches[i % _pitches.length], _rates[i % _rates.length]);
}
