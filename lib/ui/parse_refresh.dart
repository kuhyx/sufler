import 'dart:typed_data';

import 'package:sufler/import/parser_version.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/services.dart';

/// Shown on opening a script stored before parse versions were kept: it
/// has no document to re-read, so only a re-import can refresh it.
const String reimportHint =
    'Ten skrypt ma starszą wersję parsowania: zaimportuj plik ponownie, '
    'a czasy, nagrania i oceny przejdą do nowych kwestii.';

/// Stores a just-imported [fresh] parse (with its document [bytes]). A
/// re-import of a stored script replaces its parse when it differs, moving
/// the user's data; returns the summary to show, if any.
Future<String?> storeImport(
  Services svc,
  Script fresh, {
  Uint8List? bytes,
}) async {
  final lib = svc.library;
  if (bytes != null) await lib.saveSource(fresh.id, bytes);
  final existing = await lib.loadScript(fresh.id);
  if (existing == null) {
    await lib.saveScript(fresh);
    await lib.saveMeta(fresh);
    return null;
  }
  final meta = await lib.loadMeta(fresh.id);
  if (meta.fingerprint == fresh.fingerprint) {
    await lib.saveMeta(fresh); // same parse, maybe a newer version number
    return null;
  }
  return parseSummary(await lib.replaceParse(existing, fresh));
}

/// On opening script [id]: re-parses its kept document when this app's
/// parser is newer than the one that made it. Returns the summary (or the
/// re-import hint for scripts with no kept document), null when current.
Future<String?> refreshStaleParse(Services svc, String id) async {
  final lib = svc.library;
  final meta = await lib.loadMeta(id);
  if (meta.version >= parserVersion) return null;
  final source = await lib.loadSource(id);
  final script = await lib.loadScript(id);
  if (script == null) return null;
  if (source == null) return meta.fingerprint == null ? reimportHint : null;
  final fresh = await svc.importDocument(
    fileName: script.source,
    bytes: source,
  );
  if (fresh.id != id) return null; // a different document: leave it
  return await storeImport(svc, fresh);
}
