import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/voices.dart';

/// Engine errors that only report our own [TtsSpeech.stop] (the browser's
/// `speechSynthesis.cancel()`); stop() already ended that utterance.
const _stopErrors = {'interrupted', 'canceled'};

/// Polish device TTS. Pitch and rate come from the character's [Voice].
///
/// Completion is tracked through flutter_tts's handlers, not
/// `awaitSpeakCompletion(true)`: on web (4.2.5) an utterance that errors
/// drops that completer, so `speak()` never returns and the rehearsal hangs
/// on the partner line. Chromium on Linux without speech-dispatcher has no
/// voices and fails every utterance that way ("synthesis-failed").
class TtsSpeech implements Speech {
  /// Creates the speech output; [tts] is injectable for tests.
  new({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  Future<void>? _ready;
  Completer<void>? _utterance;

  Future<void> _init() async {
    _tts
      ..setCompletionHandler(_finish)
      // stop() finishes the utterance itself; a late cancel is stale.
      ..setCancelHandler(() {})
      ..setErrorHandler((message) {
        if (!_stopErrors.contains('$message')) {
          _finish(SpeechFailure('$message'));
        }
      });
    await _tts.setLanguage('pl-PL');
    await _tts.awaitSpeakCompletion(false);
  }

  void _finish([SpeechFailure? failure]) {
    final done = _utterance;
    _utterance = null;
    if (done == null || done.isCompleted) return;
    if (failure == null) {
      done.complete();
    } else {
      done.completeError(failure);
    }
  }

  @override
  Future<void> speak(String text, Voice voice, double speed) async {
    await (_ready ??= _init());
    await _tts.setPitch(voice.pitch);
    // Android's scale has 0.5 = normal; the Web Speech API has 1.0 = normal.
    final rate = voice.rateAt(speed);
    await _tts.setSpeechRate(kIsWeb ? rate * 2 : rate); // coverage:ignore-line
    final done = _utterance = Completer<void>();
    unawaited(_tts.speak(text));
    await done.future;
  }

  @override
  Future<void> stop() async {
    _finish();
    await _tts.stop();
  }
}
