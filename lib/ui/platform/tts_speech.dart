// coverage:ignore-file
// Platform glue over flutter_tts; needs a real TTS engine (device/browser).
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/voices.dart';

/// Polish device TTS. Pitch and rate come from the character's [Voice].
class TtsSpeech implements Speech {
  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  Future<void> _init() async {
    await _tts.setLanguage('pl-PL');
    await _tts.awaitSpeakCompletion(true);
  }

  @override
  Future<void> speak(String text, Voice voice, double speed) async {
    await (_ready ??= _init());
    await _tts.setPitch(voice.pitch);
    // Android's scale has 0.5 = normal; the Web Speech API has 1.0 = normal.
    final rate = voice.rateAt(speed);
    await _tts.setSpeechRate(kIsWeb ? rate * 2 : rate);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
