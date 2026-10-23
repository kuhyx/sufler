import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/voices.dart';

import 'fixture.dart';

void main() {
  final script = fixtureScript();

  test('each character gets a distinct, stable voice', () {
    final a = voiceFor(script, script.lines[1]); // elf
    final b = voiceFor(script, script.lines[2]); // wolf
    expect(a == b, isFalse);
    expect(voiceFor(script, script.lines[5]), a);
    expect(a.hashCode, voiceFor(script, script.lines[5]).hashCode);
    expect(a.pitch, inInclusiveRange(0.5, 2));
    expect(a.rate, inInclusiveRange(0.3, 0.7));
  });

  test('unattributed lines use the neutral narrator voice', () {
    expect(voiceFor(script, script.lines[7]), narratorVoice);
  });

  test('unknown speaker ids fall back to narrator', () {
    const line = ScriptLine(
      index: 0,
      speakers: ['ghost'],
      text: 'Bu',
      kind: LineKind.dialogue,
    );
    expect(voiceFor(script, line), narratorVoice);
  });

  test('speed scales the rate within TTS bounds', () {
    final v = voiceFor(script, script.lines[1]);
    expect(v.rateAt(1.5), closeTo(v.rate * 1.5, 1e-9));
    expect(v.rateAt(3), lessThanOrEqualTo(1));
    expect(v.toString(), contains('pitch'));
  });
}
