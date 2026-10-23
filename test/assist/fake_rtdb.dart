import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// RTDB REST in memory: `GET/PUT/DELETE <base>/<path>.json?auth=`, server
/// timestamps resolved from [serverMs], and RTDB's habit of keeping no
/// null or empty nodes. [onPut] lets a test play the PC.
class FakeRtdb {
  /// The whole database.
  Map<String, Object?> tree = {};

  /// Server time handed out for `{".sv": "timestamp"}`.
  int serverMs = 1700000000000;

  /// Every request, as `METHOD path`.
  final List<String> log = [];

  /// Auth tokens seen.
  final Set<String?> tokens = {};

  /// Called after each PUT with the path and the stored value.
  void Function(String path, Object? value)? onPut;

  /// The client to hand to `RtdbClient`.
  late final http.Client client = MockClient((r) async {
    tokens.add(r.url.queryParameters['auth']);
    final path = r.url.path.substring(1).replaceAll(RegExp(r'\.json$'), '');
    log.add('${r.method} $path');
    switch (r.method) {
      case 'GET':
        return _ok(read(path));
      case 'PUT':
        final stored = _clean(_resolve(jsonDecode(r.body)));
        write(path, stored);
        onPut?.call(path, stored);
        return _ok(stored);
      case 'DELETE':
        write(path, null);
        return _ok(null);
    }
    return http.Response('nope', 405);
  });

  http.Response _ok(Object? value) =>
      http.Response.bytes(utf8.encode(jsonEncode(value)), 200);

  Object? _resolve(Object? v) => switch (v) {
    {'.sv': 'timestamp'} => serverMs,
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _resolve(e.value),
    },
    final List<Object?> l => [for (final e in l) _resolve(e)],
    _ => v,
  };

  Object? _clean(Object? v) {
    if (v is Map<String, Object?>) {
      final out = {
        for (final e in v.entries)
          if (_clean(e.value) case final c?) e.key: c,
      };
      return out.isEmpty ? null : out;
    }
    if (v is List && v.isEmpty) return null;
    return v;
  }

  /// The value at [path] (slash-separated), or null.
  Object? read(String path) {
    Object? node = tree;
    for (final part in path.split('/').where((p) => p.isNotEmpty)) {
      if (node is! Map<String, Object?>) return null;
      node = node[part];
    }
    return node;
  }

  /// Writes (null: removes) [value] at [path].
  void write(String path, Object? value) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    var node = tree;
    for (final part in parts.take(parts.length - 1)) {
      node = (node[part] ??= <String, Object?>{})! as Map<String, Object?>;
    }
    if (value == null) {
      node.remove(parts.last);
    } else {
      node[parts.last] = value;
    }
    tree = (_clean(tree) as Map<String, Object?>?) ?? {};
  }
}
