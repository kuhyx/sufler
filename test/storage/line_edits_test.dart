import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/line_edits.dart';
import 'package:sufler/storage/migrate.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/reparse.dart';

import '../rehearsal/fixture.dart';
import 'pack_zip_test.dart' show fixturePackZip;
import 'reparse_test.dart' show newerParse;

var _n = 0;
ScriptLibrary _lib() =>
    ScriptLibrary(IdbStore(idbFactoryMemory, dbName: 'line-edits${_n++}'));

/// The fixture stored with a pack (clips 1 and 2) stamped for it.
Future<ScriptLibrary> _stored() async {
  final lib = _lib();
  await lib.saveScript(fixtureScript());
  await lib.saveMeta(fixtureScript());
  await lib.savePack(
    'abc123',
    fixturePackZip(fingerprint: fixtureScript().fingerprint),
  );
  return lib;
}

const _edited = 'Witaj, szary zwierzu z lasu';

void main() {
  test('a text edit is saved, logged with the old text, and only that '
      "line's clip leaves the pack", () async {
    final lib = await _stored();
    final r = await lib.correctLine(fixtureScript(), 1, text: _edited);
    expect(r.hadClip, isTrue);
    expect(r.script.lines[1].text, _edited);
    expect((await lib.loadScript('abc123'))!.lines[1].text, _edited);
    expect(await lib.loadCorrections('abc123'), [
      {'op': 'line', 'index': 1, 'text': _edited, 'was': 'Dzień dobry, Wilku!'},
    ]);
    expect(await lib.editedLines('abc123'), {1});
    final pack = (await lib.loadPack('abc123'))!;
    expect(pack.clip(1), isNull);
    expect(pack.clip(2), [2, 2, 2]);
    // The corrected script still accepts the (re-stamped) pack.
    expect(checkPack(r.script, pack).pack, isNotNull);
    expect(checkPack(r.script, pack).message, isNull);
  });

  test('a speaker correction re-stamps the pack too', () async {
    final lib = await _stored();
    final r = await lib.correctLine(fixtureScript(), 2, speakers: [elf]);
    final pack = (await lib.loadPack('abc123'))!;
    expect(checkPack(r.script, pack).pack, isNotNull);
    expect(pack.indices, [1]);
  });

  test('a clip rendered for the edited line replaces it in the pack', () async {
    final lib = await _stored();
    final r = await lib.correctLine(fixtureScript(), 1, text: _edited);
    final pack = await lib.storeLineClip(r.script, 1, Uint8List.fromList([7]));
    expect(pack!.clip(1), [7]);
    final stored = (await lib.loadPack('abc123'))!;
    expect(stored.clip(1), [7]);
    expect(stored.clip(2), [2, 2, 2]);
    expect(checkPack(r.script, stored).message, isNull);
  });

  test('a re-parse keeps a reworded line: edit replayed, its note and new '
      'clip moved with it', () async {
    final lib = await _stored();
    final r = await lib.correctLine(fixtureScript(), 1, text: _edited);
    await lib.storeLineClip(r.script, 1, Uint8List.fromList([7]));
    await lib.addNote(
      'abc123',
      1,
      const LineNote(about: 'szary', text: 'kolor wilka'),
    );
    await lib.replaceParse(r.script, newerParse());
    final s = (await lib.loadScript('abc123'))!;
    expect(s.lines[1].text, _edited);
    final prefs = await lib.loadPrefs('abc123');
    expect(prefs.notes[1]!.single.text, 'kolor wilka');
    expect((await lib.loadPack('abc123'))!.clip(1), [7]);
    expect(await lib.editedLines('abc123'), {1});
  });

  test('notes move with their line and survive the JSON round trip', () {
    const prefs = RehearsalPrefs(
      notes: {
        5: [LineNote(about: 'dobrze', text: 'przysłówek')],
      },
    );
    final again = RehearsalPrefs.fromJson(prefs.toJson());
    expect(again.notes[5]!.single.about, 'dobrze');
    expect(const RehearsalPrefs().toJson().containsKey('notes'), isFalse);
    final moved = movePrefs(again, {5: 6}, 10);
    expect(moved.prefs.notes.keys, [6]);
    expect(moved.moved, {5});
  });
}
