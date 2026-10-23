import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/anki/sufler_cards.dart';
import 'package:sufler/model/role.dart';

import 'fixture.dart';

void main() {
  final script = fixtureScript();

  test('one card per spoken line of mine, directions skipped', () {
    final deck = buildDeck(script, annaAndSong);
    expect(deck.title, 'Sztuka');
    expect(deck.cards.map((c) => c.key), [
      'abc123|1',
      'abc123|4',
      'abc123|5',
      'abc123|6',
      'abc123|7',
      'abc123|8',
    ]);
    expect(deck.cards.first.back, 'Dzień dobry.');
  });

  test('first line is cued by the start of its section', () {
    final first = buildDeck(script, annaAndSong).cards.first;
    expect(first.front, contains('(początek)'));
    expect(first.front, contains('Scena 1'));
  });

  test('cue skips stage directions and names the speaker', () {
    final card = buildDeck(script, annaAndSong).cards[1];
    expect(card.front, contains('Bartek'));
    expect(card.front, contains('Cześć, Anno.'));
    expect(card.front, isNot(contains('Wchodzi')));
    expect(card.back, 'Jak się masz?<br>Dobrze?');
  });

  test('a cue that is also mine is labelled as yours', () {
    final card = buildDeck(script, annaAndSong).cards[2];
    expect(card.front, contains('Ty'));
    expect(card.front, contains('Dobrze?'));
  });

  test('unattributed and multi-speaker lines get readable labels', () {
    final cards = buildDeck(script, {const Role.character('bartek')}).cards;
    // Bartek's line 8 is cued by the unattributed chorus lyric 7.
    expect(cards.last.front, contains('Chór'));
    expect(cards.last.back, 'Koniec &lt;b&gt;.');
    final anna = buildDeck(script, {const Role.character('anna')}).cards;
    // Anna's line 8 is shared with Bartek; its cue is the chorus too.
    expect(anna.last.key, 'abc123|8');
  });

  test('subdeck per scene', () {
    final decks = buildDeck(script, annaAndSong).cards.map((c) => c.deck);
    expect(decks, [
      'Sztuka::Scena 1',
      'Sztuka::Scena 1',
      'Sztuka::Scena 2',
      'Sztuka::Scena 2',
      'Sztuka::Scena 2',
      'Sztuka::Scena 2',
    ]);
  });

  test('cue audio is attached when the pack has the clip', () {
    final deck = buildDeck(
      script,
      annaAndSong,
      audio: fixturePack(script.id, [2, 4, 5]),
    );
    expect(deck.cards[1].front, contains('[sound:sufler-abc123-2.ogg]'));
    expect(deck.cards[0].front, isNot(contains('[sound:')));
    expect(deck.cards[4].front, isNot(contains('[sound:')));
    expect(
      deck.media.keys,
      unorderedEquals([
        'sufler-abc123-2.ogg',
        'sufler-abc123-4.ogg',
        'sufler-abc123-5.ogg',
      ]),
    );
  });

  test('deck survives a JSON round trip (the web -> wrapper hop)', () {
    final deck = buildDeck(
      script,
      annaAndSong,
      audio: fixturePack(script.id, [2]),
    );
    final copy = deckFromJson(deck.toJson());
    expect(copy.title, deck.title);
    expect(copy.cards.map((c) => c.front), deck.cards.map((c) => c.front));
    expect(
      copy.media['sufler-abc123-2.ogg'],
      deck.media['sufler-abc123-2.ogg'],
    );
  });

  test('no roles, no cards', () {
    expect(buildDeck(script, {}).cards, isEmpty);
  });
}
