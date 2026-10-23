import 'package:flutter/foundation.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/migrate.dart';
import 'package:sufler/storage/pack_zip.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/reparse.dart';

/// What [LineEdits.correctLine] did: the corrected script, the stored pack
/// now (null: none) and whether the line had a clip before.
typedef LineEditResult = ({Script script, AudioPack? pack, bool hadClip});

/// Manual line corrections and per-line notes on a stored script.
///
/// A correction changes [Script.fingerprint], so the stored voice pack is
/// re-stamped with it at once: clips of lines whose text and speakers are
/// unchanged stay, the corrected line's clip goes (it says the old text or
/// has the old voice) until a new one is rendered for it
/// ([storeLineClip]). The pack is never rejected for a correction.
extension LineEdits on ScriptLibrary {
  /// Corrects line [index] of stored [script] ([text]: the text before is
  /// logged with it), saves and logs it, and re-stamps the pack.
  Future<LineEditResult> correctLine(
    Script script,
    int index, {
    String? text,
    List<String>? speakers,
    LineKind? kind,
  }) async {
    final before = script.lines[index];
    final next = editLine(
      script,
      index,
      text: text,
      speakers: speakers,
      kind: kind,
    );
    final hadClip = (await loadPack(script.id))?.clip(index) != null;
    await saveScript(next);
    await logCorrection(
      script.id,
      lineCorrection(
        index,
        speakers: speakers,
        kind: kind,
        text: text,
        was: text == null ? null : before.text,
      ),
    );
    final pack = await restampPack(script, next);
    return (script: next, pack: pack, hadClip: hadClip);
  }

  /// Moves the stored pack of [old] to its corrected form [fresh] (same
  /// line indices): a pack stamped for [old] keeps the clips of lines
  /// whose text and speakers did not change and is stamped for [fresh];
  /// an unstamped one loses those clips and stays unstamped; one stamped
  /// for another parse (already refused) is left alone. Returns the pack
  /// as stored now.
  Future<AudioPack?> restampPack(Script old, Script fresh) async {
    final pack = await loadPack(old.id);
    final print = pack?.fingerprint;
    if (pack == null || (print != null && print != old.fingerprint)) {
      return pack;
    }
    final keep = <int, int>{};
    for (final i in pack.indices) {
      if (i >= old.lines.length || i >= fresh.lines.length) continue;
      final (a, b) = (old.lines[i], fresh.lines[i]);
      if (a.text == b.text && listEquals(a.speakers, b.speakers)) keep[i] = i;
    }
    if (keep.length == pack.length && print == fresh.fingerprint) return pack;
    final zip = rekeyPack(pack, keep, print == null ? null : fresh.fingerprint);
    await savePack(old.id, zip);
    return AudioPack.fromZip(zip);
  }

  /// Stores [clip], rendered for line [index] of [script] as it is now, in
  /// the script's pack in place of the old clip. Null (nothing stored) when
  /// there is no pack or it belongs to another parse.
  Future<AudioPack?> storeLineClip(
    Script script,
    int index,
    Uint8List clip,
  ) async {
    final pack = await loadPack(script.id);
    final print = pack?.fingerprint;
    if (pack == null || (print != null && print != script.fingerprint)) {
      return null;
    }
    final zip = packWithClip(pack, index, clip);
    await savePack(script.id, zip);
    return AudioPack.fromZip(zip);
  }

  /// Lines of script [id] corrected by hand ("zmieniono").
  Future<Set<int>> editedLines(String id) async => {
    for (final c in await loadCorrections(id))
      if (c['op'] == 'line') c['index']! as int,
  };

  /// Adds [note] to line [index] of script [id].
  Future<RehearsalPrefs> addNote(String id, int index, LineNote note) =>
      updatePrefs(id, (p) => p.withNote(index, note));
}
