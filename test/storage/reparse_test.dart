import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/import/parser_version.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/align.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/migrate.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/parse_refresh.dart';

import '../rehearsal/fixture.dart';
import 'pack_zip_test.dart' show fixturePackZip;

var _n = 0;
ScriptLibrary _lib() =>
    ScriptLibrary(IdbStore(idbFactoryMemory, dbName: 'reparse${_n++}'));

/// [s] with its lines replaced and re-indexed.
Script withLines(Script s, List<ScriptLine> lines) => Script(
  id: s.id,
  title: s.title,
  source: s.source,
  characters: s.characters,
  scenes: s.scenes,
  songs: s.songs,
  lines: [
    for (final (i, l) in lines.indexed)
      ScriptLine(
        index: i,
        speakers: l.speakers,
        text: l.text,
        kind: l.kind,
        sceneId: l.sceneId,
        songId: l.songId,
        directions: l.directions,
      ),
  ],
);

/// A newer parser: a "Finał" heading appears at 3, line 5 gains a word,
/// "Hej hej" (9) disappears.
Script newerParse() {
  final l = fixtureScript().lines;
  return withLines(fixtureScript(), [
    ...l.sublist(0, 3),
    const ScriptLine(
      index: 0,
      speakers: [],
      text: 'Finał',
      kind: LineKind.heading,
    ),
    ...l.sublist(3, 5),
    l[5].copyWith(text: 'No dobrze więc.'),
    ...l.sublist(6, 9),
    l[10],
  ]);
}

Uint8List _wav(int n) => pcmToWav(Uint8List(n * 320), sampleRate: 16000);

void main() {
  test('alignment follows shifted, reworded and removed lines', () {
    final map = alignLines(fixtureScript().lines, newerParse().lines);
    expect(map, {
      0: 0, 1: 1, 2: 2, 3: 4, 4: 5, 5: 6, //
      6: 7, 7: 8, 8: 9, 10: 10,
    });
  });

  test(
    're-parse moves timings, recordings, grades, range; replays fixes',
    () async {
      final lib = _lib();
      final old = fixtureScript();
      await lib.saveScript(old);
      await lib.saveRecording('abc123', 7, _wav(7));
      await lib.saveRecording('abc123', 8, _wav(8));
      await lib.updatePrefs(
        'abc123',
        (p) => p
            .copyWith(
              roles: {const Role.character(wolf)},
              lineSeconds: {4: 9},
              resume: const ResumePoint(
                label: 'Scena 2',
                start: 6,
                end: 10,
              ).at(2),
            )
            .graded(2, ok: false)
            .graded(9, ok: true),
      );
      // A manual correction made in the old parse.
      await lib.logCorrection(
        'abc123',
        lineCorrection(3, kind: LineKind.dialogue, speakers: [wolf]),
      );
      await lib.saveScript(
        editLine(old, 3, kind: LineKind.dialogue, speakers: [wolf]),
      );

      final fresh = newerParse();
      final u = await lib.replaceParse(
        (await lib.loadScript('abc123'))!,
        fresh,
      );
      expect(u, (
        moved: 3,
        lost: 1,
        corrections: 1,
        changed: 0,
        clipsDropped: 0,
      ));
      expect(
        parseSummary(u),
        'Zaktualizowano parsowanie: 3 kwestie przeniesione, 1 utraconych, '
        '1 poprawka ponowiona',
      );

      final p = await lib.loadPrefs('abc123');
      expect(p.lineSeconds, {5: 9.0});
      expect(p.knowledge, {
        2: [false],
      });
      expect(p.roles, {const Role.character(wolf)});
      expect(p.resume!.start, 7);
      expect(p.resume!.end, 10);
      expect(p.resume!.position, 2);
      // Lines 7 and 8 keep their own clips at 8 and 9 (old key 8 was reused).
      final secs = await lib.recordingSeconds(p);
      expect(secs.keys.toSet(), {8, 9});
      expect(secs[8], wavSeconds(_wav(7)));
      expect(secs[9], wavSeconds(_wav(8)));

      final s = (await lib.loadScript('abc123'))!;
      expect(s.lines[4].text, 'Wilk siada.');
      expect(s.lines[4].kind, LineKind.dialogue);
      expect(s.lines[4].speakers, [wolf]);
      expect(s.lines[3].text, 'Finał');
      expect(await lib.loadCorrections('abc123'), [
        lineCorrection(4, kind: LineKind.dialogue, speakers: [wolf]),
      ]);
      final meta = await lib.loadMeta('abc123');
      expect(meta.version, parserVersion);
      expect(meta.fingerprint, fresh.fingerprint);
      expect(await lib.store.keys('backup/abc123/'), hasLength(1));

      await lib.deleteScript('abc123');
      expect(await lib.store.keys(''), isEmpty);
    },
  );

  test('a lost line keeps its clip in the backup', () async {
    final lib = _lib();
    await lib.saveScript(fixtureScript());
    await lib.saveRecording('abc123', 9, _wav(3));
    final u = await lib.replaceParse(fixtureScript(), newerParse());
    expect(u.lost, 1);
    expect((await lib.loadPrefs('abc123')).recordings, isEmpty);
    expect(await lib.store.readBytes('backup/abc123/rec/9'), _wav(3));
  });

  test('legacy scripts (no log): merges are re-applied from aliases', () async {
    final lib = _lib();
    final merged = mergeCharacter(fixtureScript(), from: elf, into: wolf);
    await lib.saveScript(merged);
    final u = await lib.replaceParse(merged, newerParse());
    expect(u.corrections, 1);
    final s = (await lib.loadScript('abc123'))!;
    expect(s.characters.map((c) => c.id), [wolf]);
    expect(s.lines[1].speakers, [wolf]);
  });

  test('an old pack keeps only clips of unchanged lines, re-keyed', () async {
    final lib = _lib();
    await lib.saveScript(fixtureScript());
    // Stamped for the stored parse: clips 1, 2 and 8 ("Śpiewam ja", now 9).
    await lib.savePack(
      'abc123',
      fixturePackZip(extra: 8, fingerprint: fixtureScript().fingerprint),
    );
    final u = await lib.replaceParse(fixtureScript(), newerParse());
    expect(u.clipsDropped, 0);
    final pack = (await lib.loadPack('abc123'))!;
    expect(pack.fingerprint, (await lib.loadScript('abc123'))!.fingerprint);
    expect(pack.indices.toSet(), {1, 2, 9});
    expect(pack.clip(8), isNull); // "La la la" never gets another clip
  });

  test('a changed line loses its clip; legacy edits are counted', () async {
    final lib = _lib();
    final old = editLine(fixtureScript(), 1, speakers: [wolf]);
    await lib.saveScript(old);
    await lib.savePack('abc123', fixturePackZip(fingerprint: old.fingerprint));
    final u = await lib.replaceParse(old, newerParse());
    // Line 1's speakers differ (a manual fix from before the log).
    expect(u.changed, 1);
    expect(u.clipsDropped, 1);
    expect((await lib.loadPack('abc123'))!.indices, [2]);
    expect(
      parseSummary(u),
      'Zaktualizowano parsowanie: 0 kwestii przeniesionych, 0 utraconych, '
      '1 kwestia z innym przypisaniem (sprawdź „Popraw tekst”; poprzednia '
      'wersja jest w kopii), 1 głos do wygenerowania',
    );
  });

  test('an unstamped pack is dropped on re-parse', () async {
    final lib = _lib();
    await lib.saveScript(fixtureScript());
    await lib.savePack('abc123', fixturePackZip());
    final u = await lib.replaceParse(fixtureScript(), newerParse());
    expect(u.clipsDropped, 2);
    expect(await lib.loadPack('abc123'), isNull);
  });

  test('summary wording', () {
    expect(
      parseSummary((
        moved: 1,
        lost: 0,
        corrections: 0,
        changed: 0,
        clipsDropped: 0,
      )),
      'Zaktualizowano parsowanie: 1 kwestia przeniesiona, 0 utraconych',
    );
    expect(
      parseSummary((
        moved: 5,
        lost: 0,
        corrections: 0,
        changed: 0,
        clipsDropped: 0,
      )),
      'Zaktualizowano parsowanie: 5 kwestii przeniesionych, 0 utraconych',
    );
    expect(
      parseSummary((
        moved: 22,
        lost: 2,
        corrections: 0,
        changed: 0,
        clipsDropped: 0,
      )),
      'Zaktualizowano parsowanie: 22 kwestie przeniesione, 2 utraconych',
    );
  });
}
