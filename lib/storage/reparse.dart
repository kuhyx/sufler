import 'package:flutter/foundation.dart';

import 'package:sufler/import/parser_version.dart';
import 'package:sufler/model/json.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/align.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/migrate.dart';
import 'package:sufler/storage/pack_zip.dart';

/// Parse bookkeeping of a stored script: [parserVersion] that made it (0:
/// before versions) and the fingerprint of that raw parse (before manual
/// corrections), null when unknown.
typedef ParseMeta = ({int version, String? fingerprint});

/// What a re-parse did to the user's data: lines whose data moved / was
/// lost, corrections replayed, aligned spoken lines whose speakers or kind
/// now differ from the stored script (parser changes, or manual fixes from
/// before the correction log), voice clips dropped (their line changed).
typedef ParseUpdate = ({
  int moved,
  int lost,
  int corrections,
  int changed,
  int clipsDropped,
});

/// Source documents, parse metadata and the correction log, next to the
/// library's scripts (keys `source/<id>`, `meta/<id>`, `edits/<id>`,
/// `backup/<id>/<ms>`).
extension ParseStore on ScriptLibrary {
  /// Parse metadata of script [id].
  Future<ParseMeta> loadMeta(String id) async {
    final j = await store.readJson('meta/$id');
    return (
      version: j?['parserVersion'] as int? ?? 0,
      fingerprint: j?['parseFingerprint'] as String?,
    );
  }

  /// Records that [raw] (an uncorrected parse) is the current parse of
  /// script [id], made by this app's [parserVersion].
  Future<void> saveMeta(Script raw) => store.writeJson('meta/${raw.id}', {
    'parserVersion': parserVersion,
    'parseFingerprint': raw.fingerprint,
  });

  /// Keeps the imported document, so a newer parser can re-read it.
  Future<void> saveSource(String id, Uint8List bytes) =>
      store.writeBytes('source/$id', bytes);

  /// The imported document of script [id], if kept.
  Future<Uint8List?> loadSource(String id) => store.readBytes('source/$id');

  /// The manual corrections of script [id], oldest first.
  Future<List<Correction>> loadCorrections(String id) async {
    final j = await store.readJson('edits/$id');
    return [for (final e in (j?['edits'] as List? ?? const [])) e as Json];
  }

  /// Appends [c] to script [id]'s correction log.
  Future<void> logCorrection(String id, Correction c) async {
    final log = [...await loadCorrections(id), c];
    await store.writeJson('edits/$id', {'edits': log});
  }

  /// Replaces stored [old] by the new parse [fresh] of the same document:
  /// per-line timings, recordings, grades and the resume range move to
  /// the matching new lines, corrections are replayed, and a backup of
  /// the old script and prefs is kept under `backup/<id>/<ms>`.
  Future<ParseUpdate> replaceParse(Script old, Script fresh) async {
    final id = old.id;
    final prefs = await loadPrefs(id);
    await store.writeJson(
      'backup/$id/${DateTime.now().millisecondsSinceEpoch}',
      {'script': old.toJson(), 'prefs': prefs.toJson()},
    );
    final map = alignLines(old.lines, fresh.lines);
    final logged = await loadCorrections(id);
    final meta = await loadMeta(id);
    // Before the log existed only merges can be told from parser changes.
    final log = logged.isEmpty && meta.fingerprint == null
        ? inferMerges(old, fresh)
        : logged;
    final replay = replayCorrections(fresh, log, map);
    final move = movePrefs(prefs, map, fresh.lines.length);
    // Recordings: read every moved clip before writing any, since an old
    // key may be another line's new key.
    // The clip of a line that is gone is kept with the backup.
    final clips = <int, Uint8List>{};
    final orphans = <int, Uint8List>{};
    for (final e in prefs.recordings.entries) {
      final bytes = await store.readBytes(e.value);
      if (bytes == null) continue;
      final to = move.recordings[e.key];
      if (to == null) {
        orphans[e.key] = bytes;
      } else {
        clips[to] = bytes;
      }
    }
    for (final key in prefs.recordings.values) {
      await store.delete(key);
    }
    for (final e in orphans.entries) {
      await store.writeBytes('backup/$id/rec/${e.key}', e.value);
    }
    final keys = <int, String>{};
    for (final e in clips.entries) {
      keys[e.key] = 'rec/$id/${e.key}';
      await store.writeBytes(keys[e.key]!, e.value);
    }
    final changed = map.entries.where((e) {
      final (a, b) = (old.lines[e.key], replay.script.lines[e.value]);
      return a.isSpoken &&
          (a.kind != b.kind || !listEquals(a.speakers, b.speakers));
    }).length;
    final clipsDropped = await _movePack(old, replay.script, map);
    await saveScript(replay.script);
    await savePrefs(id, move.prefs.copyWith(recordings: keys));
    await store.writeJson('edits/$id', {'edits': replay.log});
    await saveMeta(fresh);
    return (
      moved: move.moved.length,
      lost: move.lost.length,
      corrections: replay.applied,
      changed: changed,
      clipsDropped: clipsDropped,
    );
  }

  /// Keeps the clips of lines whose text and speakers are unchanged, under
  /// their new indices and stamped for [fresh]; returns how many went.
  /// A pack not stamped for [old] is dropped whole.
  /// Without this an old pack would play clip N for a different line N.
  Future<int> _movePack(Script old, Script fresh, Map<int, int> map) async {
    final pack = await loadPack(old.id);
    if (pack == null) return 0;
    final keep = <int, int>{};
    // Only a pack stamped for the stored parse says which line a clip is
    // for; an unstamped one may come from yet another parse: drop it.
    final known = pack.fingerprint == old.fingerprint;
    for (final i in known ? pack.indices : const <int>[]) {
      final to = map[i];
      if (to == null || i >= old.lines.length) continue;
      final (a, b) = (old.lines[i], fresh.lines[to]);
      if (a.text == b.text && listEquals(a.speakers, b.speakers)) keep[i] = to;
    }
    if (keep.isEmpty) {
      await store.delete('pack/${old.id}');
    } else {
      await savePack(old.id, rekeyPack(pack, keep, fresh.fingerprint));
    }
    return pack.length - keep.length;
  }
}
