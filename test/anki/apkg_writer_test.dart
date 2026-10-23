import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sufler/anki/export_apkg.dart';

import 'fixture.dart';

/// An unpacked `.apkg`: the opened collection plus the media map and files.
class Unpacked {
  Unpacked(this.db, this.media, this.files, this._dir);

  final Database db;
  final Map<String, Object?> media;
  final Map<String, List<int>> files;
  final Directory _dir;

  void close() {
    db.close();
    _dir.deleteSync(recursive: true);
  }
}

Unpacked unpack(Uint8List apkg) {
  final archive = ZipDecoder().decodeBytes(apkg);
  final dir = Directory.systemTemp.createTempSync('sufler_apkg_test');
  final path = '${dir.path}/collection.anki2';
  File(path).writeAsBytesSync(archive.findFile('collection.anki2')!.content);
  final media =
      jsonDecode(utf8.decode(archive.findFile('media')!.content))
          as Map<String, Object?>;
  return Unpacked(sqlite3.open(path), media, {
    for (final f in archive.files) f.name: f.content,
  }, dir);
}

void main() {
  final script = fixtureScript();

  test('apkg opens with sqlite3: notes, cards, fronts, backs', () async {
    final apkg = unpack(await exportApkg(script, annaAndSong));
    addTearDown(apkg.close);
    final notes = apkg.db.select('SELECT guid, flds FROM notes ORDER BY id');
    expect(notes, hasLength(6));
    expect(apkg.db.select('SELECT id FROM cards'), hasLength(6));
    final backs = [for (final n in notes) (n['flds'] as String).split('\x1f')];
    expect(
      backs.map((f) => f[1]),
      containsAll(['Dzień dobry.', 'Ja też.', 'La la la']),
    );
    expect(apkg.media, isEmpty);
  });

  test('cards land in per-scene subdecks', () async {
    final apkg = unpack(await exportApkg(script, annaAndSong));
    addTearDown(apkg.close);
    final decks =
        jsonDecode(
              apkg.db.select('SELECT decks FROM col').single['decks'] as String,
            )
            as Map<String, Object?>;
    final names = {
      for (final d in decks.values.cast<Map<String, Object?>>())
        d['id']! as int: d['name']! as String,
    };
    expect(
      names.values,
      containsAll(['Default', 'Sztuka', 'Sztuka::Scena 1', 'Sztuka::Scena 2']),
    );
    final perDeck = <String, int>{};
    for (final row in apkg.db.select('SELECT did FROM cards')) {
      final name = names[row['did'] as int]!;
      perDeck[name] = (perDeck[name] ?? 0) + 1;
    }
    expect(perDeck, {'Sztuka::Scena 1': 2, 'Sztuka::Scena 2': 4});
  });

  test('guids and ids are stable across two exports', () async {
    Future<List<Object?>> ids() async {
      final apkg = unpack(await exportApkg(script, annaAndSong));
      addTearDown(apkg.close);
      return [
        for (final r in apkg.db.select(
          'SELECT n.id, n.guid, c.id AS cid, c.did FROM notes n '
          'JOIN cards c ON c.nid = n.id ORDER BY n.id',
        ))
          [r['id'], r['guid'], r['cid'], r['did']],
      ];
    }

    final first = await ids();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await ids(), first);
    // A different script must not collide with this one's notes.
    final other = unpack(
      await exportApkg(fixtureScript(id: 'zzz'), annaAndSong),
    );
    addTearDown(other.close);
    final otherGuids = other.db
        .select('SELECT guid FROM notes')
        .map((r) => r['guid']);
    expect(
      otherGuids.toSet().intersection(
        first.map((r) => (r! as List)[1]).toSet(),
      ),
      isEmpty,
    );
  });

  test('media map lists the cue clips of the pack', () async {
    final apkg = unpack(
      await exportApkg(
        script,
        annaAndSong,
        audio: fixturePack(script.id, [2, 4, 5, 8]),
      ),
    );
    addTearDown(apkg.close);
    expect(
      apkg.media.values,
      unorderedEquals([
        'sufler-abc123-2.ogg',
        'sufler-abc123-4.ogg',
        'sufler-abc123-5.ogg',
      ]),
    );
    for (final entry in apkg.media.entries) {
      final index = (entry.value! as String).split('-').last.split('.').first;
      expect(utf8.decode(apkg.files[entry.key]!), 'OggS-clip-$index');
    }
    final fronts = apkg.db
        .select('SELECT flds FROM notes')
        .map((r) => (r['flds'] as String).split('\x1f').first);
    expect(fronts.where((f) => f.contains('[sound:')), hasLength(3));
  });
}
