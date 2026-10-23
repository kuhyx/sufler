import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/prefs.dart';

import '../rehearsal/fixture.dart';
import 'pack_zip_test.dart' show fixturePackZip;

var _n = 0;
ScriptLibrary _lib() =>
    ScriptLibrary(IdbStore(idbFactoryMemory, dbName: 'lib${_n++}'));

void main() {
  test('scripts persist and list; delete removes everything', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'shared');
    final lib = ScriptLibrary(store);
    expect(await lib.scripts(), isEmpty);
    await lib.saveScript(fixtureScript());
    await lib.savePrefs('abc123', const RehearsalPrefs(speed: 2));
    await lib.savePack('abc123', fixturePackZip());
    await lib.saveRecording(
      'abc123',
      2,
      pcmToWav(Uint8List(32000), sampleRate: 16000),
    );

    // A fresh library over the same store sees it all (app restart).
    final again = ScriptLibrary(store);
    final scripts = await again.scripts();
    expect(scripts.single.title, 'Krasnale testowe');
    expect((await again.loadScript('abc123'))!.lines.length, 11);
    expect((await again.loadPrefs('abc123')).speed, 2);
    expect((await again.loadPack('abc123'))!.length, 2);

    await again.deleteScript('abc123');
    expect(await again.scripts(), isEmpty);
    expect(await again.loadScript('abc123'), isNull);
    expect(await again.loadPack('abc123'), isNull);
    expect((await again.loadPrefs('abc123')).speed, 1);
    expect(await store.keys('rec/abc123/'), isEmpty);
  });

  test('recording sets the prefs key and its duration', () async {
    final lib = _lib();
    final wav = pcmToWav(Uint8List(48000), sampleRate: 16000); // 1.5 s
    final key = await lib.saveRecording('abc123', 4, wav);
    final prefs = await lib.loadPrefs('abc123');
    expect(prefs.recordings, {4: key});
    expect(await lib.loadRecording(key), wav);
    expect(await lib.recordingSeconds(prefs), {4: 1.5});
    await lib.deleteRecording('abc123', 4);
    final after = await lib.loadPrefs('abc123');
    expect(after.recordings, isEmpty);
    expect(await lib.loadRecording(key), isNull);
    expect(await lib.recordingSeconds(after), isEmpty);
  });

  test('recordingSeconds skips recordings whose bytes vanished', () async {
    final lib = _lib();
    expect(
      await lib.recordingSeconds(const RehearsalPrefs(recordings: {1: 'gone'})),
      isEmpty,
    );
  });

  test('prefs and settings round trip through the store', () async {
    final lib = _lib();
    final prefs = RehearsalPrefs(
      roles: {const Role.character('piaskowy-wilk')},
      speed: 0.5,
      lineSeconds: const {2: 9},
    );
    await lib.savePrefs('abc123', prefs);
    final back = await lib.loadPrefs('abc123');
    expect(back.toJson(), prefs.toJson());
    expect((await lib.loadSettings()).cleanTarget, 3);
    await lib.saveSettings(const AppSettings(cleanTarget: 7, loop: true));
    expect((await lib.loadSettings()).cleanTarget, 7);
  });

  test('a corrupt pack reads as no pack', () async {
    final lib = _lib();
    await lib.savePack('x', Uint8List.fromList([1, 2, 3]));
    expect(await lib.loadPack('x'), isNull);
  });

  test('start script: the remembered one, else the only one', () async {
    final lib = _lib();
    expect(await lib.startScriptId(), isNull);
    await lib.saveScript(fixtureScript());
    // A library from before "last script" existed: its only script.
    expect(await lib.startScriptId(), 'abc123');
    final other = fixtureScript();
    await lib.saveScript(
      Script(
        id: 'zzz',
        title: 'Inna',
        source: 'b.txt',
        characters: other.characters,
        scenes: other.scenes,
        songs: other.songs,
        lines: other.lines,
      ),
    );
    expect(await lib.startScriptId(), isNull);
    await lib.rememberScript('zzz');
    await lib.rememberScript('zzz');
    expect(await lib.startScriptId(), 'zzz');
    await lib.deleteScript('zzz');
    expect(await lib.startScriptId(), 'abc123');
  });

  test('updatePrefs keeps fields the caller did not touch', () async {
    final lib = _lib();
    await lib.savePrefs('a', const RehearsalPrefs(speed: 2));
    await lib.updatePrefs('a', (p) => p.graded(3, ok: false));
    final p = await lib.loadPrefs('a');
    expect(p.speed, 2);
    expect(p.missed, {3});
  });
}
