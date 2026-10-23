import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sufler/model/json.dart';
import 'package:sufler/storage/store.dart';

/// [Store] as flat files in [root] (app documents dir on Android).
/// A key becomes one URI-encoded file name: `<key>.json` or `<key>.bin`.
class FileStore implements Store {
  /// Stores files under [root], created on first write.
  FileStore(this.root);

  /// Directory holding every record.
  final Directory root;

  File _file(String key, String ext) =>
      File('${root.path}/${Uri.encodeComponent(key)}.$ext');

  Future<File> _writable(String key, String ext) async {
    await root.create(recursive: true);
    return _file(key, ext);
  }

  @override
  Future<Json?> readJson(String key) async {
    final f = _file(key, 'json');
    if (!f.existsSync()) return null;
    return jsonDecode(await f.readAsString()) as Json;
  }

  @override
  Future<void> writeJson(String key, Json value) async {
    await (await _writable(key, 'json')).writeAsString(jsonEncode(value));
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final f = _file(key, 'bin');
    return f.existsSync() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    await (await _writable(key, 'bin')).writeAsBytes(bytes);
  }

  @override
  Future<void> delete(String key) async {
    for (final ext in ['json', 'bin']) {
      final f = _file(key, ext);
      if (f.existsSync()) await f.delete();
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    if (!root.existsSync()) return const [];
    final out = <String>[];
    await for (final e in root.list()) {
      final name = e.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final key = Uri.decodeComponent(name.substring(0, dot));
      if (key.startsWith(prefix)) out.add(key);
    }
    return out;
  }
}
