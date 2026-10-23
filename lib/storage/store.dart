import 'dart:typed_data';

import 'package:sufler/model/json.dart';

/// Key-value persistence: JSON records and raw byte blobs side by side.
///
/// Keys are slash-separated paths (`script/<id>`, `rec/<id>/<line>`).
/// Implementations: [FileStore]-style files on io, IndexedDB on web.
abstract interface class Store {
  /// The JSON stored under [key], or null.
  Future<Json?> readJson(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> writeJson(String key, Json value);

  /// The bytes stored under [key], or null.
  Future<Uint8List?> readBytes(String key);

  /// Stores [bytes] under [key], replacing any previous value.
  Future<void> writeBytes(String key, Uint8List bytes);

  /// Removes [key] (JSON or bytes); a missing key is fine.
  Future<void> delete(String key);

  /// Every key (JSON or bytes) starting with [prefix].
  Future<List<String>> keys(String prefix);
}
