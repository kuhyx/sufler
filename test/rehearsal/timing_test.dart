import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/timing.dart';

void main() {
  group('syllableCount', () {
    test('counts every Polish vowel letter, case-insensitive', () {
      // Pia-sko-we (4: i a o e) Wil-ki (2) nie (2) je-dzą (2) Kras-na-li (3)
      expect(syllableCount('Piaskowe Wilki nie jedzą Krasnali!'), 13);
      expect(syllableCount('ĄĘÓ óąę'), 6);
      expect(syllableCount('...!?'), 0);
    });
  });

  group('defaultPauseSeconds', () {
    test('syllables/3.5 x 1.6 + 1.5', () {
      expect(
        defaultPauseSeconds('Piaskowe Wilki nie jedzą Krasnali!'),
        closeTo(13 / 3.5 * 1.6 + 1.5, 1e-9),
      );
      expect(
        defaultPauseSeconds('Piaskowe Wilki nie jedzą Krasnali!'),
        closeTo(7.442857, 1e-6),
      );
      expect(defaultPauseSeconds(''), 1.5);
    });

    test('speed multiplier divides the default pause', () {
      expect(
        defaultPauseSeconds('Naprawdę.', speed: 2),
        closeTo((3 / 3.5 * 1.6 + 1.5) / 2, 1e-9),
      );
    });

    test('speed is clamped to 0.5..3', () {
      expect(defaultPauseSeconds('', speed: 10), 0.5);
      expect(defaultPauseSeconds('', speed: 0.1), 3);
    });
  });

  group('pauseSeconds precedence', () {
    const text = 'Naprawdę.';
    final formula = defaultPauseSeconds(text);

    test('formula when nothing else is set', () {
      expect(pauseSeconds(index: 4, text: text), formula);
    });

    test('recording length + 1 s beats the formula, ignores speed', () {
      expect(
        pauseSeconds(
          index: 4,
          text: text,
          speed: 2,
          recordingSeconds: {4: 2.5},
        ),
        3.5,
      );
    });

    test('manual override beats recording and ignores speed', () {
      expect(
        pauseSeconds(
          index: 4,
          text: text,
          speed: 3,
          overrides: {4: 12},
          recordingSeconds: {4: 2.5},
        ),
        12,
      );
    });

    test('other lines keep the formula', () {
      expect(
        pauseSeconds(
          index: 5,
          text: text,
          overrides: {4: 12},
          recordingSeconds: {4: 2.5},
        ),
        formula,
      );
    });
  });
}
