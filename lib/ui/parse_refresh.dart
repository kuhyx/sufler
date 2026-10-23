import 'dart:typed_data';

import 'package:sufler/import/parser_version.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/labels.dart';
import 'package:sufler/ui/services.dart';

/// One line for the user, e.g. "Zaktualizowano parsowanie: 2 kwestie
/// przeniesione, 0 utraconych", plus what else changed.
String parseSummary(ParseUpdate u) {
  const reassigned =
      'z innym przypisaniem (sprawdź „Popraw tekst”; poprzednia wersja jest '
      'w kopii)';
  String n(int count, String one, String few, String many) =>
      '$count ${plural(count, one, few, many)}';
  final moved = n(
    u.moved,
    'kwestia przeniesiona',
    'kwestie przeniesione',
    'kwestii przeniesionych',
  );
  final parts = [
    moved,
    '${u.lost} utraconych',
    if (u.corrections > 0)
      n(
        u.corrections,
        'poprawka ponowiona',
        'poprawki ponowione',
        'poprawek ponowionych',
      ),
    if (u.changed > 0)
      '${n(u.changed, 'kwestia', 'kwestie', 'kwestii')} $reassigned',
    if (u.clipsDropped > 0)
      '${n(u.clipsDropped, 'głos', 'głosy', 'głosów')} do wygenerowania',
  ];
  return 'Zaktualizowano parsowanie: ${parts.join(', ')}';
}

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

/// On opening script [id]: re-parses its document when this app's parser
/// is newer than the one that made it. The document is the kept one or,
/// for scripts stored before documents were kept, the copy the file picker
/// left on the device. Returns the summary, null when nothing changed
/// (no document anywhere: the old parse stays, Narzędzia offers a pick).
Future<String?> refreshStaleParse(Services svc, String id) async {
  final lib = svc.library;
  final meta = await lib.loadMeta(id);
  if (meta.version >= parserVersion) return null;
  final script = await lib.loadScript(id);
  if (script == null) return null;
  final kept = await lib.loadSource(id);
  final bytes =
      kept ?? await svc.findPickedCopy(fileName: script.source, id: id);
  if (bytes == null) return null;
  final fresh = await svc.importDocument(fileName: script.source, bytes: bytes);
  if (fresh.id != id) return null; // a different document: leave it
  return await storeImport(svc, fresh, bytes: kept == null ? bytes : null);
}

/// Whether script [id] has an old parse and no document to re-read.
Future<bool> needsSourceFile(Services svc, String id) async {
  final lib = svc.library;
  final meta = await lib.loadMeta(id);
  return meta.version < parserVersion && await lib.loadSource(id) == null;
}

/// "Odśwież parsowanie": the user picks script [id]'s document, which is
/// re-parsed and kept. Null when cancelled; throws [FormatException] for
/// another document.
Future<String?> refreshFromFile(Services svc, String id) async {
  final file = await svc.files.pick(['pdf', 'docx', 'odt', 'txt']);
  if (file == null) return null;
  final fresh = await svc.importDocument(
    fileName: file.name,
    bytes: file.bytes,
  );
  if (fresh.id != id) {
    throw const FormatException('To inny plik niż ten skrypt');
  }
  return await storeImport(svc, fresh, bytes: file.bytes) ??
      'Parsowanie jest aktualne';
}
