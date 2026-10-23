import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/rehearsal/similarity.dart';

void main() {
  test('normalisation ignores case, punctuation and spacing', () {
    expect(normalizedWords('Piaskowe Wilki, nie jedzą… KRASNALI!'), [
      'piaskowe',
      'wilki',
      'nie',
      'jedzą',
      'krasnali',
    ]);
    expect(
      wordSimilarity(
        'Piaskowe Wilki nie jedzą Krasnali!',
        'piaskowe wilki nie jedzą krasnali',
      ),
      1,
    );
    expect(wordSimilarity('', '...'), 1);
    expect(wordSimilarity('Tak', ''), 0);
  });

  test('one wrong word in five is 0.8: still ✓; two is ✗', () {
    const line = 'Piaskowe Wilki nie jedzą Krasnali';
    expect(wordSimilarity(line, 'Piaskowe Wilki nie lubią Krasnali'), 0.8);
    expect(suggestedGrade(line, 'piaskowe wilki nie lubią krasnali'), isTrue);
    expect(suggestedGrade(line, 'piaskowe psy nie lubią krasnali'), isFalse);
    // A dropped word counts as one edit too.
    expect(suggestedGrade(line, 'Piaskowe Wilki nie jedzą'), isTrue);
    expect(suggestedGrade(line, null), isNull);
  });

  test('a transcript of a later line is recognised as a skip', () {
    const current = 'Dzień dobry Wilku';
    const later = ['Naprawdę nie wiem co robić', 'No dobrze wracajmy'];
    expect(matchesOther(current, 'no dobrze wracajmy', later), 1);
    // Close to the expected line: not a skip, even if similar to another.
    expect(matchesOther(current, 'dzień dobry wilku', later), isNull);
    // Matches nothing well: a bad take, not a skip.
    expect(matchesOther(current, 'zupełnie coś innego', later), isNull);
    expect(matchesOther(current, null, later), isNull);
  });
}
