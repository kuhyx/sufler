import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/vad.dart';

const _rate = 16000;

/// Synthetic PCM16: [seconds] of a 220 Hz tone at [amp] (0 = silence),
/// plus deterministic low noise so the floor is not zero.
Uint8List pcm(List<(double seconds, int amp)> parts) {
  final rnd = math.Random(7);
  final samples = <int>[];
  for (final (seconds, amp) in parts) {
    final n = (seconds * _rate).round();
    for (var i = 0; i < n; i++) {
      final tone = amp * math.sin(2 * math.pi * 220 * i / _rate);
      samples.add((tone + rnd.nextInt(201) - 100).round());
    }
  }
  final out = ByteData(samples.length * 2);
  for (final (i, s) in samples.indexed) {
    out.setInt16(i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Feeds [bytes] in 100 ms chunks; returns the elapsed time when it ended.
double? feed(SpeechEndpoint vad, Uint8List bytes) {
  const chunk = _rate ~/ 10 * 2;
  for (var i = 0; i < bytes.length; i += chunk) {
    if (vad.add(bytes.sublist(i, math.min(i + chunk, bytes.length)))) {
      return vad.elapsed;
    }
  }
  return null;
}

void main() {
  test('speech burst then silence: start, end, ended after 1 s', () {
    final vad = SpeechEndpoint(sampleRate: _rate);
    final at = feed(vad, pcm([(0.8, 0), (1.2, 8000), (2, 0)]));
    expect(vad.speechStart, closeTo(0.8, 0.021));
    expect(vad.speechEnd, closeTo(2.0, 0.021));
    expect(at, closeTo(3.0, 0.11));
    expect(vad.speechEnd! - vad.speechStart!, closeTo(1.2, 0.04));
  });

  test('not over before a full second of silence', () {
    final vad = SpeechEndpoint(sampleRate: _rate);
    expect(feed(vad, pcm([(0.6, 0), (0.5, 8000), (0.9, 0)])), isNull);
    expect(vad.ended, isFalse);
    expect(vad.speechStart, closeTo(0.6, 0.021));
  });

  test('pauses between words do not end the line', () {
    final vad = SpeechEndpoint(sampleRate: _rate);
    feed(vad, pcm([(0.6, 0), (0.4, 6000), (0.6, 0), (0.5, 6000), (1.1, 0)]));
    expect(vad.ended, isTrue);
    expect(vad.speechStart, closeTo(0.6, 0.021));
    expect(vad.speechEnd, closeTo(2.1, 0.021));
  });

  test('a short click is forgotten; the real line is measured', () {
    final vad = SpeechEndpoint(sampleRate: _rate);
    feed(vad, pcm([(0.6, 0), (0.1, 9000), (1.2, 0)]));
    expect(vad.ended, isFalse);
    expect(vad.speechStart, isNull);
    feed(vad, pcm([(0.7, 7000), (1.1, 0)]));
    expect(vad.ended, isTrue);
    expect(vad.speechStart, closeTo(1.9, 0.021));
    expect(vad.speechEnd, closeTo(2.6, 0.021));
  });

  test('the noise floor is calibrated: steady hum is not speech', () {
    final vad = SpeechEndpoint(sampleRate: _rate);
    feed(vad, pcm([(3, 1500)]));
    expect(vad.speechStart, isNull);
    expect(vad.threshold, greaterThan(0.01));
    expect(vad.level, greaterThan(0));
    // Speech well above the hum still counts.
    feed(vad, pcm([(0.5, 20000), (1.1, 1500)]));
    expect(vad.ended, isTrue);
    expect(vad.speechStart, closeTo(3.0, 0.021));
  });
}
