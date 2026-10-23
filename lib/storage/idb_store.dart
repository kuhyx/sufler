import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/storage/store.dart';

const _json = 'json';
const _bytes = 'bytes';

/// [Store] on IndexedDB (web), or any idb_shim backend (memory in tests).
/// JSON is stored as a string; bytes as a Uint8List value.
class IdbStore implements Store {
  /// Opens database [dbName] through [factory] lazily on first use.
  new(this.factory, {this.dbName = 'sufler'});

  /// The IndexedDB implementation.
  final IdbFactory factory;

  /// Database name.
  final String dbName;

  Future<Database>? _db;

  Future<Database> get _open => _db ??= factory.open(
    dbName,
    version: 1,
    onUpgradeNeeded: (e) {
      e.database
        ..createObjectStore(_json)
        ..createObjectStore(_bytes);
    },
  );

  Future<Object?> _get(String store, String key) async {
    final txn = (await _open).transaction(store, idbModeReadOnly);
    final value = await txn.objectStore(store).getObject(key);
    await txn.completed;
    return value;
  }

  Future<void> _put(String store, String key, Object value) async {
    final txn = (await _open).transaction(store, idbModeReadWrite);
    await txn.objectStore(store).put(value, key);
    await txn.completed;
  }

  @override
  Future<Json?> readJson(String key) async {
    final raw = await _get(_json, key);
    return raw == null ? null : jsonDecode(raw as String) as Json;
  }

  @override
  Future<void> writeJson(String key, Json value) =>
      _put(_json, key, jsonEncode(value));

  @override
  Future<Uint8List?> readBytes(String key) async {
    final raw = await _get(_bytes, key);
    return raw == null ? null : Uint8List.fromList((raw as List).cast<int>());
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) =>
      _put(_bytes, key, bytes);

  @override
  Future<void> delete(String key) async {
    final txn = (await _open).transaction([_json, _bytes], idbModeReadWrite);
    await txn.objectStore(_json).delete(key);
    await txn.objectStore(_bytes).delete(key);
    await txn.completed;
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final txn = (await _open).transaction([_json, _bytes], idbModeReadOnly);
    final all = [
      ...await txn.objectStore(_json).getAllKeys(),
      ...await txn.objectStore(_bytes).getAllKeys(),
    ];
    await txn.completed;
    return [
      for (final k in all)
        if ((k as String).startsWith(prefix)) k,
    ];
  }
}
