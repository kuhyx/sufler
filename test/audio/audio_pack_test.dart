import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/audio_pack.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('reads manifest and clips; missing clip reads as null', () {
    final manifest = jsonEncode({
      'scriptId': 's1',
      'engine': 'chatterbox-multilingual@0.1.7',
      'voices': {'wilk': 'v3'},
      'lines': {'4': 'audio/4.ogg', '9': 'audio/9.ogg'},
    });
    final pack = AudioPack.fromZip(
      _zip({
        'manifest.json': utf8.encode(manifest),
        'audio/4.ogg': [1, 2, 3],
      }),
    );
    expect(pack.scriptId, 's1');
    expect(pack.voices, {'wilk': 'v3'});
    expect(pack.clip(4), [1, 2, 3]);
    expect(pack.clip(9), isNull);
    expect(pack.length, 1);
  });

  test('a zip without manifest is rejected', () {
    expect(
      () => AudioPack.fromZip(
        _zip({
          'x.txt': [0],
        }),
      ),
      throwsFormatException,
    );
  });
}
