import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/storage/file_store.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/store.dart';

/// The same contract for every backend.
void _contract(String name, Future<Store> Function() open) {
  group(name, () {
    late Store store;
    setUp(() async => store = await open());

    test('json round trip, missing key reads null', () async {
      expect(await store.readJson('script/a'), isNull);
      await store.writeJson('script/a', {'x': 1, 'y': 'ź'});
      expect(await store.readJson('script/a'), {'x': 1, 'y': 'ź'});
      await store.writeJson('script/a', {'x': 2});
      expect(await store.readJson('script/a'), {'x': 2});
    });

    test('bytes round trip', () async {
      expect(await store.readBytes('rec/a/1'), isNull);
      final data = Uint8List.fromList([0, 1, 255, 7]);
      await store.writeBytes('rec/a/1', data);
      expect(await store.readBytes('rec/a/1'), data);
    });

    test('keys by prefix, delete removes json and bytes', () async {
      await store.writeJson('script/a', {});
      await store.writeJson('script/b', {});
      await store.writeJson('prefs/a', {});
      await store.writeBytes('rec/a/1', Uint8List(1));
      await store.writeBytes('rec/a/2', Uint8List(1));
      expect((await store.keys('script/'))..sort(), ['script/a', 'script/b']);
      expect((await store.keys('rec/a/'))..sort(), ['rec/a/1', 'rec/a/2']);
      await store.delete('script/a');
      await store.delete('rec/a/1');
      await store.delete('nothing/here');
      expect(await store.keys('script/'), ['script/b']);
      expect(await store.keys('rec/a/'), ['rec/a/2']);
      expect(await store.readBytes('rec/a/1'), isNull);
    });
  });
}

void main() {
  var n = 0;
  _contract(
    'IdbStore (memory)',
    () async => IdbStore(idbFactoryMemory, dbName: 'test${n++}'),
  );
  _contract('FileStore (temp dir)', () async {
    final dir = await Directory.systemTemp.createTemp('sufler_store');
    addTearDown(() => dir.delete(recursive: true));
    return FileStore(Directory('${dir.path}/nested'));
  });
}
