/// Writes an [AnkiDeck] as an Anki `.apkg` (ver-11 collection in a zip).
///
/// Ported from lyricanki's `ApkgWriter`, with two changes that matter:
/// every id is derived from the card's key / deck name ([stableId]) instead of
/// the clock, so a re-import updates notes in place; and the `media` map is
/// real (zip entries `0`, `1`, ... named by the map), for cue audio.
///
/// Uses `dart:io` + sqlite3, so it runs on Android and in the desktop
/// wrapper; the web app posts its deck to the wrapper instead.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sufler/anki/anki_deck.dart';
import 'package:sufler/anki/anki_ids.dart';
import 'package:sufler/anki/collection_config.dart';
import 'package:sufler/anki/collection_schema.dart';

/// Builds the `.apkg` bytes for [deck]. [now] stamps modification times only.
Uint8List writeApkg(AnkiDeck deck, {DateTime? now}) {
  final stamp = now ?? DateTime.now();
  final archive = Archive();
  final collection = _buildCollection(deck, stamp);
  archive.addFile(
    ArchiveFile('collection.anki2', collection.length, collection),
  );
  final mediaMap = <String, String>{};
  var n = 0;
  for (final entry in deck.media.entries) {
    final name = '${n++}';
    mediaMap[name] = entry.key;
    archive.addFile(ArchiveFile(name, entry.value.length, entry.value));
  }
  // Anki rejects an archive without the `media` entry, even an empty one.
  final media = utf8.encode(jsonEncode(mediaMap));
  archive.addFile(ArchiveFile('media', media.length, media));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Deck id for a full deck [name].
int deckIdFor(String name) => stableId('deck|$name');

/// Every deck the cards need, parents included ("A::B" also needs "A").
Map<int, String> _deckTree(AnkiDeck deck) {
  final names = <String>{deck.title};
  for (final card in deck.cards) {
    final parts = card.deck.split('::');
    for (var i = 1; i <= parts.length; i++) {
      names.add(parts.take(i).join('::'));
    }
  }
  return {for (final name in names) deckIdFor(name): name};
}

/// sqlite3 has no in-memory serialise binding here, so the collection is
/// built in a temporary directory and read back (proven on Android in
/// lyricanki).
Uint8List _buildCollection(AnkiDeck deck, DateTime now) {
  final dir = Directory.systemTemp.createTempSync('sufler_apkg');
  final path = '${dir.path}/collection.anki2';
  try {
    final db = sqlite3.open(path);
    try {
      db.execute(collectionSchema);
      _insertCollectionRow(db, deck, now);
      _insertNotes(db, deck.cards, now);
    } finally {
      db.close();
    }
    return File(path).readAsBytesSync();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _insertCollectionRow(Database db, AnkiDeck deck, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  // Creation time is in seconds, everything else in milliseconds.
  db.execute(
    'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, '
    'decks, dconf, tags) VALUES (1, ?, ?, ?, ?, 0, 0, 0, ?, ?, ?, ?, ?)',
    <Object?>[
      nowMs ~/ 1000,
      nowMs,
      nowMs,
      ankiSchemaVersion,
      buildConfJson(),
      buildModelsJson(defaultDeck: deckIdFor(deck.title)),
      buildDecksJson(_deckTree(deck)),
      buildDconfJson(),
      '{}',
    ],
  );
}

void _insertNotes(Database db, List<AnkiCard> cards, DateTime now) {
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
  final noteStmt = db.prepare(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
    'flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, ?)',
  );
  final cardStmt = db.prepare(
    'INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, '
    'factor, reps, lapses, left, odue, odid, flags, data) '
    'VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?)',
  );
  try {
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final noteId = stableId('note|${card.key}');
      noteStmt.execute(<Object?>[
        noteId,
        guidFor(card.key),
        modelId,
        nowSeconds,
        'sufler',
        [card.front, card.back].join(fieldSeparator),
        card.front,
        csumFor(card.front),
        '',
      ]);
      // New card (type 0, queue 0); due = position, so study order follows
      // the script.
      cardStmt.execute(<Object?>[
        stableId('card|${card.key}'),
        noteId,
        deckIdFor(card.deck),
        nowSeconds,
        i,
        '',
      ]);
    }
  } finally {
    noteStmt.close();
    cardStmt.close();
  }
}
