import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/voices.dart';
import 'package:sufler/ui/platform/tts_speech.dart';

/// Mimics flutter_tts 4.2.5 on web: with awaitSpeakCompletion(true), an
/// utterance that errors (Chromium without speech-dispatcher has no voices:
/// "synthesis-failed") drops its completer, so speak() never completes.
class _FakeTts extends Fake implements FlutterTts {
  bool awaiting = false;
  VoidCallback? onComplete;
  VoidCallback? onCancel;
  ErrorHandler? onError;
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async =>
      awaiting = awaitCompletion;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  void setCompletionHandler(VoidCallback callback) => onComplete = callback;
  @override
  void setCancelHandler(VoidCallback callback) => onCancel = callback;
  @override
  void setErrorHandler(ErrorHandler handler) => onError = handler;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken.add(text);
    return awaiting ? Completer<dynamic>().future : Future.value(1);
  }

  @override
  Future<dynamic> stop() async => stops++;
}

const _voice = Voice(1, 0.5);

void main() {
  test('an utterance that errors fails speak() instead of hanging', () async {
    final tts = _FakeTts();
    final speech = TtsSpeech(tts: tts);
    final said = speech.speak('Dzień dobry', _voice, 1);
    await pumpEventQueue();
    tts.onError?.call('synthesis-failed');
    await expectLater(
      said.timeout(const Duration(seconds: 1)),
      throwsA(isA<SpeechFailure>()),
    );
  });

  test('completes when the engine reports the utterance done', () async {
    final tts = _FakeTts();
    final speech = TtsSpeech(tts: tts);
    final said = speech.speak('Dzień dobry', _voice, 1);
    await pumpEventQueue();
    tts.onComplete?.call();
    await said.timeout(const Duration(seconds: 1));
    expect(tts.spoken, ['Dzień dobry']);
  });

  test('stop() ends a pending utterance; a stale cancel/interrupt is '
      'ignored', () async {
    final tts = _FakeTts();
    final speech = TtsSpeech(tts: tts);
    final first = speech.speak('Raz', _voice, 1);
    await pumpEventQueue();
    await speech.stop();
    await first.timeout(const Duration(seconds: 1));
    final second = speech.speak('Dwa', _voice, 1);
    await pumpEventQueue();
    // The browser reports the cancelled utterance late, as an error.
    tts
      ..onError?.call('interrupted')
      ..onCancel?.call();
    var finished = false;
    unawaited(second.then((_) => finished = true));
    await pumpEventQueue();
    expect(finished, isFalse);
    tts.onComplete?.call();
    await second.timeout(const Duration(seconds: 1));
    expect(tts.stops, 1);
  });
}
