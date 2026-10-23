// coverage:ignore-file
// Platform glue: a browser keeps no copy of picked files.
import 'dart:typed_data';

/// Web: nothing to find; an old script waits for "Odśwież parsowanie".
Future<Uint8List?> findPickedCopy({
  required String fileName,
  required String id,
}) async => null;
