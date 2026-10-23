import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/pace.dart';

import 'fixture.dart';

void main() {
  group('spokenSyllables', () {
    test('one per vowel; "i" before a vowel only softens', () {
      expect(spokenSyllables('się'), 1);
      expect(spokenSyllables('nie'), 1);
      expect(spokenSyllables('dzień'), 1);
      expect(spokenSyllables('ciocia'), 2);
      expect(spokenSyllables('Piaskowe'), 3);
      expect(spokenSyllables('nauka'), 3);
      expect(spokenSyllables('historii'), 3);
      expect(spokenSyllables('i'), 1);
      expect(spokenSyllables('Wilki'), 2);
    });

    test('case-insensitive, Polish letters, no vowels = 0', () {
      expect(spokenSyllables('ŻÓŁW'), 1);
      expect(spokenSyllables('ĄĘÓ'), 3);
      expect(spokenSyllables('PIES'), 1);
      expect(spokenSyllables(''), 0);
      expect(spokenSyllables('...!?'), 0);
    });

    test('a sentence', () {
      // Pia-sko-we (3) Wil-ki (2) nie (1) je-dzą (2) Kra-sna-li (3)
      expect(spokenSyllables('Piaskowe Wilki nie jedzą Krasnali!'), 11);
    });
  });

  group('median', () {
    test('odd and even counts', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median([5]), 5);
    });
  });

  group('secondsPerSyllable', () {
    final script = fixtureScript();
    // Line syllables: 1 "Dzień dobry, Wilku!" 5, 4 "Naprawdę." 3,
    // 5 "No dobrze." 3, 2 (the Wilki sentence) 11.

    test('median of seconds / syllable over the recorded lines', () {
      expect(
        secondsPerSyllable(script, {1: 2.5, 4: 1.2, 5: 0.9}),
        closeTo(0.4, 1e-9),
      );
      expect(
        secondsPerSyllable(script, {1: 2.5, 4: 1.2, 5: 0.9, 2: 11}),
        closeTo((0.4 + 0.5) / 2, 1e-9),
      );
    });

    test('fewer than $minPaceSamples recordings: no estimate', () {
      expect(secondsPerSyllable(script, const {}), isNull);
      expect(secondsPerSyllable(script, {1: 2.5, 4: 1.2}), isNull);
    });

    test('empty takes and stale indices are not samples', () {
      // 3 "Wilk siada." (3) counts; a 0 s take and line 99 (gone) do not.
      expect(secondsPerSyllable(script, {1: 2.5, 4: 0, 99: 3, 3: 1}), isNull);
      expect(
        secondsPerSyllable(script, {1: 2.5, 4: 0, 3: 1.2, 5: 0.9}),
        closeTo(0.4, 1e-9),
      );
    });
  });
}
