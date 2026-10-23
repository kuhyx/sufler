import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/rehearsal/run_split.dart';
import 'package:sufler/rehearsal/wav.dart';

const _lines = ['Raz dwa trzy cztery.', 'Pięć sześć.', 'Ala ma kota'];

/// One word per second from [at]: "raz" 0-1 s, "dwa" 1-2 s, ...
List<TimedWord> _words(List<String> said, {double at = 0}) => [
  for (final (i, w) in said.indexed)
    (text: ' $w', start: at + i.toDouble(), end: at + i + 0.9),
];

List<(double, double)> _r(List<Span> spans) => [
  for (final s in spans)
    ((s.start * 100).round() / 100, (s.end * 100).round() / 100),
];

/// [seconds] of silence, [loud] seconds of a 440 Hz tone, then silence.
Uint8List _wav({double before = 1, double loud = 2, double after = 1}) {
  const rate = 16000;
  final n = ((before + loud + after) * rate).round();
  final pcm = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final on = t >= before && t < before + loud;
    final v = on ? (math.sin(2 * math.pi * 440 * t) * 12000).round() : 0;
    pcm.setInt16(i * 2, v, Endian.little);
  }
  return pcmToWav(pcm.buffer.asUint8List(), sampleRate: rate);
}

void main() {
  group('splitBySyllables', () {
    test('cuts the span by each line\'s syllable share, back to back', () {
      // 5, 2 and 5 syllables: 12 shares over 0..12 s.
      final spans = splitBySyllables(_lines, 0, 12);
      expect(_r(spans), [(0.0, 5.0), (5.0, 7.0), (7.0, 12.0)]);
    });

    test('a line without vowels still gets one share', () {
      expect(_r(splitBySyllables(['Hm', 'Ala'], 1, 4)), [
        (1.0, 2.0),
        (2.0, 4.0),
      ]);
    });
  });

  group('alignToLines', () {
    test('exact words: each line runs from its first word to its last', () {
      final words = _words(
        'raz dwa trzy cztery pięć sześć ala ma kota'.split(' '),
        at: 0.5,
      );
      final spans = alignToLines(_lines, words, from: 0, to: 10);
      expect(_r(spans), [(0.5, 4.4), (4.5, 6.4), (6.5, 9.4)]);
    });

    test('misheard, missing and extra words still land on their line', () {
      // "trzy" misheard, "cztery" dropped, "no" inserted, "ma" dropped.
      final words = _words('raz dwa czy no pięć sześć ala kota'.split(' '));
      final spans = alignToLines(_lines, words, from: 0, to: 9);
      expect(_r(spans), [(0.0, 3.9), (4.0, 5.9), (6.0, 7.9)]);
    });

    test('a line nobody heard shares the gap between its neighbours', () {
      final words =
          _words(['raz', 'dwa', 'trzy', 'cztery']) +
          [(text: 'kota', start: 8.0, end: 9.0)];
      final spans = alignToLines(_lines, words, from: 0, to: 9);
      // Line 2 ("pięć sześć") is silent: it gets 3.9 .. 8.0.
      expect(_r(spans), [(0.0, 3.9), (3.9, 8.0), (8.0, 9.0)]);
    });

    test('one word heard as two tokens keeps one time', () {
      final words = [
        (text: 'Raz-dwa', start: 0.0, end: 1.0),
        (text: 'trzy cztery,', start: 1.0, end: 2.0),
        (text: 'pięć', start: 2.0, end: 2.5),
        (text: 'sześć.', start: 2.5, end: 3.0),
        (text: 'Ala ma kota', start: 3.0, end: 4.0),
      ];
      expect(_r(alignToLines(_lines, words, from: 0, to: 4)), [
        (0.0, 2.0),
        (2.0, 3.0),
        (3.0, 4.0),
      ]);
    });
  });

  group('speechSpan', () {
    test('finds the loud part of a take', () {
      final span = speechSpan(_wav())!;
      expect(span.start, closeTo(1, 0.05));
      expect(span.end, closeTo(3, 0.05));
    });

    test('silence: null', () {
      expect(speechSpan(_wav(loud: 0)), isNull);
    });
  });
}
