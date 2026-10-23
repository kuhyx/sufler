/// A finished deck, independent of the script model.
///
/// This is the hand-off format between "which cards" (`sufler_cards.dart`,
/// which needs the Flutter-flavoured model) and "write the .apkg"
/// (`apkg_writer.dart`, which needs sqlite). Keeping it model-free is what
/// lets the desktop wrapper, a plain Dart CLI with no `dart:ui`, build the
/// apkg for the web app from this JSON.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sufler/model/json.dart';

/// One note with one card.
@immutable
class AnkiCard {
  /// Creates a card.
  const new({
    required this.key,
    required this.deck,
    required this.front,
    required this.back,
  });

  /// Parses [json] produced by [toJson].
  factory fromJson(Json json) => AnkiCard(
    key: json['key']! as String,
    deck: json['deck']! as String,
    front: json['front']! as String,
    back: json['back']! as String,
  );

  /// Stable identity (`<scriptId>|<lineIndex>`); guid and ids derive from it.
  final String key;

  /// Full deck path, `::`-separated.
  final String deck;

  /// Front field (HTML), may hold a `[sound:...]` tag.
  final String front;

  /// Back field (HTML).
  final String back;

  /// JSON form.
  Json toJson() => {'key': key, 'deck': deck, 'front': front, 'back': back};
}

/// A deck tree to export: cards plus the media files they reference.
@immutable
class AnkiDeck {
  /// Creates a deck.
  const new({required this.title, required this.cards, this.media = const {}});

  /// Root deck name; card decks are `<title>::<subdeck>` or [title] itself.
  final String title;

  /// Cards in study order.
  final List<AnkiCard> cards;

  /// Media file name -> bytes.
  final Map<String, Uint8List> media;

  /// JSON form; media is base64.
  Json toJson() => {
    'title': title,
    'cards': [for (final c in cards) c.toJson()],
    'media': {for (final e in media.entries) e.key: base64Encode(e.value)},
  };
}

/// Parses a deck produced by [AnkiDeck.toJson].
AnkiDeck deckFromJson(Json json) => AnkiDeck(
  title: json['title']! as String,
  cards: objectList(json['cards'], AnkiCard.fromJson),
  media: {
    for (final e in ((json['media'] as Json?) ?? const {}).entries)
      e.key: base64Decode(e.value! as String),
  },
);
