import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';

/// Serialises a loaded [pack] back into the DOCS-contract zip, so a pack
/// that only exists in memory (a fresh render) can be stored as bytes.
/// Clip indices come from [script]'s lines since the pack exposes no list.
Uint8List packToZip(Script script, AudioPack pack) => _zip(pack, {
  for (final line in script.lines)
    if (pack.clip(line.index) != null) line.index: line.index,
}, pack.fingerprint);

/// [pack] with only the clips in [moves] (old line index -> new), stamped
/// with [fingerprint] (null: unstamped): what survives of a pack after a
/// re-parse or a correction.
Uint8List rekeyPack(AudioPack pack, Map<int, int> moves, String? fingerprint) =>
    _zip(pack, moves, fingerprint);

/// [pack] with [clip] as line [index]'s (added or replaced).
Uint8List packWithClip(AudioPack pack, int index, Uint8List clip) => _zip(
  pack,
  {for (final i in pack.indices) i: i},
  pack.fingerprint,
  extra: {index: clip},
);

Uint8List _zip(
  AudioPack pack,
  Map<int, int> moves,
  String? fingerprint, {
  Map<int, Uint8List> extra = const {},
}) {
  final archive = Archive();
  final lines = <String, String>{};
  final clips = {
    for (final e in moves.entries) e.value: ?pack.clip(e.key),
    ...extra,
  };
  for (final e in clips.entries) {
    final clip = e.value;
    final name = 'audio/${e.key}.ogg';
    lines['${e.key}'] = name;
    archive.add(ArchiveFile.bytes(name, clip));
  }
  final manifest = {
    'scriptId': pack.scriptId,
    'engine': pack.engine,
    'voices': pack.voices,
    'fingerprint': ?fingerprint,
    'lines': lines,
  };
  archive.add(
    ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
  );
  return ZipEncoder().encodeBytes(archive);
}
