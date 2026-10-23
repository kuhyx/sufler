import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/parse_refresh.dart';

import '../rehearsal/fixture.dart';
import 'pack_zip_test.dart' show fixturePackZip;
import 'reparse_test.dart' show newerParse;

var _n = 0;
ScriptLibrary _lib() =>
    ScriptLibrary(IdbStore(idbFactoryMemory, dbName: 'reparse-pack${_n++}'));

void main() {
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
}
