import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/storage/pack_zip.dart';

import '../rehearsal/fixture.dart';

/// A tiny pack for the fixture script: clips for lines 1 and 2 (or
/// [extra] more), stamped with [fingerprint] when given.
Uint8List fixturePackZip({String? fingerprint, int? extra}) {
  final a = Archive();
  void add(String name, List<int> bytes) =>
      a.add(ArchiveFile.bytes(name, bytes));
  add(
    'manifest.json',
    utf8.encode(
      jsonEncode({
        'scriptId': 'abc123',
        'engine': 'test@1',
        'voices': {'blystek': 'v1'},
        'fingerprint': ?fingerprint,
        'lines': {
          '1': 'audio/1.ogg',
          '2': 'audio/2.ogg',
          if (extra != null) '$extra': 'audio/2.ogg',
        },
      }),
    ),
  );
  add('audio/1.ogg', [1, 1]);
  add('audio/2.ogg', [2, 2, 2]);
  return ZipEncoder().encodeBytes(a);
}

void main() {
  test('packToZip rebuilds a zip that reads back identically', () {
    final pack = AudioPack.fromZip(fixturePackZip());
    final zip = packToZip(fixtureScript(), pack);
    final again = AudioPack.fromZip(zip);
    expect(again.scriptId, 'abc123');
    expect(again.engine, 'test@1');
    expect(again.voices, {'blystek': 'v1'});
    expect(again.length, 2);
    expect(again.clip(1), [1, 1]);
    expect(again.clip(2), [2, 2, 2]);
    expect(again.clip(3), isNull);
    expect(again.fingerprint, isNull);
    final stamped = AudioPack.fromZip(fixturePackZip(fingerprint: 'f'));
    expect(
      AudioPack.fromZip(packToZip(fixtureScript(), stamped)).fingerprint,
      'f',
    );
  });
}
