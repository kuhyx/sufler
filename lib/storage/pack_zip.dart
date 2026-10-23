import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';

/// Serialises a loaded [pack] back into the DOCS-contract zip, so a pack
/// that only exists in memory (a fresh render) can be stored as bytes.
/// Clip indices come from [script]'s lines since the pack exposes no list.
Uint8List packToZip(Script script, AudioPack pack) {
  final archive = Archive();
  final lines = <String, String>{};
  for (final line in script.lines) {
    final clip = pack.clip(line.index);
    if (clip == null) continue;
    final name = 'audio/${line.index}.ogg';
    lines['${line.index}'] = name;
    archive.add(ArchiveFile.bytes(name, clip));
  }
  final manifest = {
    'scriptId': pack.scriptId,
    'engine': pack.engine,
    'voices': pack.voices,
    'fingerprint': ?pack.fingerprint,
    'lines': lines,
  };
  archive.add(
    ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
  );
  return ZipEncoder().encodeBytes(archive);
}
