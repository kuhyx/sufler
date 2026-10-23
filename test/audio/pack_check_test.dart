import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/edits.dart';

import '../rehearsal/fixture.dart';
import '../storage/pack_zip_test.dart' show fixturePackZip;

void main() {
  test('fingerprint: the same rows and digest as the voice service', () {
    // tts/tests/test_fingerprint.py HAND_ROWS / HAND_DIGEST.
    const s = Script(
      id: 'x',
      title: 'T',
      source: 's',
      characters: [],
      scenes: [],
      songs: [],
      lines: [
        ScriptLine(
          index: 0,
          speakers: [],
          text: 'Scena 1',
          kind: LineKind.heading,
        ),
        ScriptLine(
          index: 1,
          speakers: ['a', 'b'],
          text: 'Zażółć gęślą',
          kind: LineKind.dialogue,
        ),
        ScriptLine(
          index: 2,
          speakers: ['a'],
          text: '',
          kind: LineKind.direction,
        ),
      ],
    );
    expect(
      s.fingerprint,
      'f910bdbe41d87489d1766643fb80adc2d6eb506a322b06d533291b3c68c88fe7',
    );
    // Any field of any line changes it.
    final edited = editLine(s, 2, kind: LineKind.dialogue);
    expect(edited.fingerprint, isNot(s.fingerprint));
  });

  test('a pack for this parse plays, even partial', () {
    final script = fixtureScript();
    final pack = AudioPack.fromZip(
      fixturePackZip(fingerprint: script.fingerprint),
    );
    expect(checkPack(script, pack), (pack: pack, message: null));
  });

  test('a pack for another parse is ignored with a message', () {
    final script = fixtureScript();
    final pack = AudioPack.fromZip(fixturePackZip(fingerprint: 'abc'));
    final r = checkPack(script, pack);
    expect(r.pack, isNull);
    expect(
      r.message,
      'Paczka głosów pochodzi z innej wersji tekstu — wygeneruj ponownie',
    );
  });

  test('an old pack without fingerprint: kept with a warning if it fits', () {
    final script = fixtureScript();
    final fits = AudioPack.fromZip(fixturePackZip());
    expect(checkPack(script, fits).pack, fits);
    expect(checkPack(script, fits).message, unversionedPackMessage);
    final beyond = AudioPack.fromZip(fixturePackZip(extra: 11));
    expect(checkPack(script, beyond).pack, isNull);
    expect(checkPack(script, beyond).message, stalePackMessage);
  });
}
