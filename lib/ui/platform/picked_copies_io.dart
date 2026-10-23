import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sufler/import/import_document.dart' show sha256Hex;

/// Android: file_picker (android_file_picker, FileUtils.openFileStream)
/// copies every picked document to `<cacheDir>/file_picker/<ms>/<name>`,
/// and `getTemporaryDirectory()` is that cacheDir. Android may evict it.
// coverage:ignore-start
Future<Uint8List?> findPickedCopy({
  required String fileName,
  required String id,
}) async {
  final cache = await getTemporaryDirectory();
  return await findCopyIn(
    Directory('${cache.path}/file_picker'),
    fileName: fileName,
    id: id,
  );
}
// coverage:ignore-end

/// The `<root>/*/<fileName>` copy whose sha256 is [id] (the script id is
/// the content hash, so an older or newer file of the same name is not
/// taken); null when none.
Future<Uint8List?> findCopyIn(
  Directory root, {
  required String fileName,
  required String id,
}) async {
  if (!root.existsSync()) return null;
  await for (final dir in root.list()) {
    if (dir is! Directory) continue;
    final file = File('${dir.path}/$fileName');
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    if (sha256Hex(bytes) == id) return bytes;
  }
  return null;
}
