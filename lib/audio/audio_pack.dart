import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sufler/model/json.dart';

/// A rendered voice pack: one Ogg/Opus clip per spoken line.
/// Format: DOCS-contract.md "Audio pack".
class AudioPack {
  new _(this.scriptId, this.engine, this.voices, this._clips);

  /// Reads a `<script-id>.sufler-audio.zip`.
  factory fromZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const FormatException('audio pack has no manifest.json');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.content)) as Json;
    final lines = manifest['lines']! as Json;
    final clips = <int, Uint8List>{};
    for (final entry in lines.entries) {
      final file = archive.findFile(entry.value! as String);
      if (file != null) clips[int.parse(entry.key)] = file.content;
    }
    return AudioPack._(
      manifest['scriptId']! as String,
      manifest['engine']! as String,
      {
        for (final e in (manifest['voices']! as Json).entries)
          e.key: e.value! as String,
      },
      clips,
    );
  }

  /// The script this pack was rendered for.
  final String scriptId;

  /// Engine and version that rendered it.
  final String engine;

  /// Character id -> voice id.
  final Map<String, String> voices;

  final Map<int, Uint8List> _clips;

  /// The clip for line [index], or null when the pack has none.
  Uint8List? clip(int index) => _clips[index];

  /// Number of clips in the pack.
  int get length => _clips.length;
}
