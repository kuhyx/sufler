import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/wav.dart';

import 'vad_test.dart' show pcm;

void main() {
  test('a take ends by itself and keeps only the speech', () {
    final take = VadTake(16000);
    final audio = pcm([(0.8, 0), (1.5, 8000), (1.2, 0)]);
    var ended = false;
    for (var i = 0; i < audio.length && !ended; i += 3200) {
      ended = take.add(audio.sublist(i, (i + 3200).clamp(0, audio.length)));
    }
    expect(ended, isTrue);
    final r = take.result(transcript: 'hej')!;
    expect(r.durationSeconds, closeTo(1.5, 0.04));
    expect(wavSeconds(r.audio!), closeTo(r.durationSeconds, 0.001));
    expect(r.transcript, 'hej');
  });

  test("the recognizer's speech times win over the detector's", () {
    final take = VadTake(16000)..add(pcm([(0.8, 0), (1.5, 8000), (1.2, 0)]));
    final r = take.result(serverStart: 1, serverEnd: 2)!;
    expect(r.speechStart, 1);
    expect(r.durationSeconds, 1);
    expect(wavSeconds(r.audio!), 1);
  });

  test('silence gives no result', () {
    final take = VadTake(16000)..add(pcm([(2, 0)]));
    expect(take.result(), isNull);
    expect(wavSeconds(take.wav()), 2);
  });
}
