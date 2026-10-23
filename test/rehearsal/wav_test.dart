import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/wav.dart';

void main() {
  test('wraps PCM16 mono in a 44-byte RIFF header', () {
    final pcm = Uint8List(32000); // 1 s at 16 kHz mono 16-bit
    final wav = pcmToWav(pcm, sampleRate: 16000);
    expect(wav.length, 44 + 32000);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    final view = ByteData.sublistView(wav);
    expect(view.getUint32(24, Endian.little), 16000);
    expect(view.getUint32(40, Endian.little), 32000);
    expect(wavSeconds(wav), 1);
  });

  test('stereo duration and garbage input', () {
    final wav = pcmToWav(
      Uint8List(16000 * 2 * 2),
      sampleRate: 16000,
      channels: 2,
    );
    expect(wavSeconds(wav), 1);
    expect(wavSeconds(Uint8List(10)), 0);
    expect(wavSeconds(Uint8List(44)), 0);
  });

  test('trim keeps the span, clamped to the audio', () {
    final pcm = Uint8List.fromList(List.generate(64000, (i) => i % 256));
    final wav = pcmToWav(pcm, sampleRate: 16000); // 2 s
    final cut = trimWav(wav, 0.5, 1.25);
    expect(wavSeconds(cut), 0.75);
    expect(cut.sublist(44, 46), pcm.sublist(16000, 16002));
    expect(wavSeconds(trimWav(wav, 1.5, 9)), 0.5);
    expect(wavSeconds(trimWav(wav, -1, 0.5)), 0.5);
    expect(wavSeconds(trimWav(wav, 1, 0.5)), 0);
  });
}
