import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/assist/ask.dart';
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/pc_link.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/pending_asks.dart';
import 'package:sufler/storage/reparse.dart';

import '../rehearsal/fixture.dart';
import '../storage/reparse_test.dart' show newerParse;

class _FakeAssistant implements Assistant {
  new(this._pc, {this.fail});

  final StreamController<bool> _pc;

  /// When set, [explain] throws it (the PC's own error, not a lost link).
  final String? fail;

  @override
  Stream<bool> get pcOnline => _pc.stream;

  @override
  Future<String> explain({
    required Script script,
    required int index,
    required String selection,
  }) async {
    if (fail != null) throw StateError(fail!);
    return 'wyjaśnienie';
  }

  @override
  Future<Uint8List?> renderLine({
    required Script script,
    required int index,
  }) async => null;
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  const index = 1;
  const selection = 'szary';

  test('an offline question is stored and answered after a restart', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'ask-restart');
    final script = fixtureScript();
    final lib1 = ScriptLibrary(store);
    await lib1.saveScript(script);
    final pc1 = StreamController<bool>.broadcast();
    Ask(
      link: PcLink.of(_FakeAssistant(pc1)),
      library: lib1,
      script: script,
      index: index,
      selection: selection,
    );
    pc1.add(false); // the PC is offline: the question waits, stored.
    await _pump();
    expect(await lib1.pendingAsks('abc123'), [
      (index: index, selection: selection),
    ]);

    // The app restarted: the same store, a new assistant, the question
    // resumed from its stored form.
    final lib2 = ScriptLibrary(store);
    final pc2 = StreamController<bool>.broadcast();
    Ask(
      link: PcLink.of(_FakeAssistant(pc2)),
      library: lib2,
      script: script,
      index: index,
      selection: selection,
      saved: true,
    );
    pc2.add(true); // the PC is back.
    await _pump();
    final prefs = await lib2.loadPrefs('abc123');
    expect(prefs.notes[index]!.single.about, selection);
    expect(prefs.notes[index]!.single.text, 'wyjaśnienie');
    expect(await lib2.pendingAsks('abc123'), isEmpty);
  });

  test('a PC error drops the stored question', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'ask-pc-error');
    final lib = ScriptLibrary(store);
    await lib.saveScript(fixtureScript());
    final pc = StreamController<bool>.broadcast();
    final ask = Ask(
      link: PcLink.of(_FakeAssistant(pc, fail: 'no such line')),
      library: lib,
      script: fixtureScript(),
      index: index,
      selection: selection,
    );
    pc.add(true); // online, so the refusal is the PC's own.
    await _pump();
    expect(ask.error, isNotNull);
    expect(await lib.pendingAsks('abc123'), isEmpty);
  });

  test('asks are de-duplicated, both survive at once, and empty keys '
      'go with their last entry', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'ask-storage');
    final lib = ScriptLibrary(store);
    await lib.saveScript(fixtureScript());
    const a = (index: index, selection: selection);
    const b = (index: 2, selection: 'wilka');
    const c = (index: 3, selection: 'lasu');
    await lib.savePendingAsk('abc123', a);
    await lib.savePendingAsk('abc123', a); // no duplicate entry
    expect(await lib.pendingAsks('abc123'), [a]);
    await Future.wait([
      lib.savePendingAsk('abc123', b),
      lib.savePendingAsk('abc123', c), // two at once: both survive
    ]);
    expect(await lib.pendingAsks('abc123'), [a, b, c]);
    await lib.dropPendingAsk('abc123', a);
    expect(await lib.pendingAsks('abc123'), [b, c]);
    await lib.dropPendingAsk('abc123', b);
    await lib.dropPendingAsk('abc123', c);
    expect(await store.readJson('asks/abc123'), isNull); // key deleted
    await lib.savePendingAsk('abc123', a);
    await lib.deleteScript('abc123');
    expect(await store.readJson('asks/abc123'), isNull); // gone with it
  });

  test('a re-parse moves stored questions with their line', () async {
    final store = IdbStore(idbFactoryMemory, dbName: 'ask-reparse');
    final lib = ScriptLibrary(store);
    await lib.saveScript(fixtureScript());
    await lib.saveMeta(fixtureScript());
    await lib.savePendingAsk('abc123', (index: 5, selection: 'dobrze'));
    await lib.replaceParse(fixtureScript(), newerParse());
    // "No dobrze." moved from 5 to 6 (a heading appeared before it).
    expect(await lib.pendingAsks('abc123'), [(index: 6, selection: 'dobrze')]);
  });
}
