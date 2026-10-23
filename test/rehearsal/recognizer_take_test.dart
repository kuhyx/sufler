import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/recognizer_take.dart';

void main() {
  test('nothing heard and no words: no take', () {
    final t = RecognizerTake()..started();
    for (var at = 0.0; at < 3; at += 0.1) {
      t.level(0, at);
    }
    expect(t.result(3), isNull);
  });

  test('words only: the take spans the whole listen', () {
    final t = RecognizerTake()..started();
    expect(t.words('ala ma kota'), isTrue);
    final r = t.result(3)!;
    expect(r.speechStart, 0);
    expect(r.speechEnd, 3);
    expect(r.transcript, 'ala ma kota');
  });

  test('levels above the floor bound the speech, even without words', () {
    final t = RecognizerTake()..started();
    for (var at = 0.0; at < 0.5; at += 0.1) {
      t.level(1, at);
    }
    t
      ..level(2, 0.5)
      ..level(8, 0.6)
      ..level(9, 1.8)
      ..level(1, 2.5);
    final r = t.result(3)!;
    expect(r.speechStart, 0.6);
    expect(r.speechEnd, 1.8);
    expect(r.transcript, '');
  });

  test(
    "the previous listen's stragglers are ignored until this one starts",
    () {
      final t = RecognizerTake();
      expect(t.live, isFalse);
      expect(t.words('stara kwestia'), isFalse);
      expect(t.text, '');
      t.started();
      expect(t.live, isTrue);
      expect(t.words('nowa'), isTrue);
      expect(t.words('nowa kwestia'), isFalse);
      expect(t.text, 'nowa kwestia');
    },
  );

  test('unusable recognizer vs nothing understood this time', () {
    for (final e in [
      'error_network',
      'error_network_timeout',
      'error_server',
      'error_server_disconnected',
      'error_language_not_supported',
      'error_language_unavailable',
      'error_audio_error',
      'error_permission',
    ]) {
      expect(recognizerUnusable(e), isTrue, reason: e);
    }
    for (final e in [
      'error_no_match',
      'error_speech_timeout',
      'error_client',
      'error_busy',
    ]) {
      expect(recognizerUnusable(e), isFalse, reason: e);
    }
  });
}
