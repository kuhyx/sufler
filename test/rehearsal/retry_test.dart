import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/session.dart';

import 'fixture.dart';

// Scene 1 for the wolf: 1 partner, 2 mine, 4 mine, 5 partner.
List<Cue> _scene1([LineRange? range]) {
  final s = fixtureScript();
  return buildCues(s, {
    const Role.character(wolf),
  }, range ?? LineRange.section(s.scenes[0]));
}

/// Plays one pass; each own line is graded [tries] in order until a ✓.
void _pass(RehearsalSession s, List<List<bool>> tries) {
  final lines = [
    for (final t in tries) [...t],
  ];
  final startPass = s.pass;
  while (s.phase != Phase.finished && s.pass == startPass) {
    switch (s.phase) {
      case Phase.partner || Phase.prompt:
        s.partnerDone();
      case Phase.mine:
        s.finishPause();
      case Phase.grade:
        final g = lines.first.removeAt(0);
        if (g) lines.removeAt(0);
        s.grade(ok: g);
      case Phase.finished:
        break;
    }
  }
}

void main() {
  test('✗ hides the line, replays the cue before it, asks again until ✓', () {
    final s = RehearsalSession(_scene1(), selfGrade: true)
      ..partnerDone()
      ..finishPause();
    expect(s.grade(ok: false), isTrue, reason: 'first attempt');
    expect(s.phase, Phase.prompt);
    expect(s.current!.line.index, 2);
    expect(s.prompt!.line.index, 1);
    s.partnerDone();
    expect(s.phase, Phase.mine);
    expect(s.current!.line.index, 2);
    s.finishPause();
    expect(s.grade(ok: false), isFalse, reason: 'a retry');
    expect(s.phase, Phase.prompt);
    s
      ..partnerDone()
      ..finishPause();
    expect(s.grade(ok: true), isFalse);
    expect(s.current!.line.index, 4);
    expect(s.phase, Phase.mine);
    expect(s.results, {1: false});
  });

  test('the prompt is the cue before, even my own; none: ask at once', () {
    final s = RehearsalSession(_scene1(), selfGrade: true)
      ..partnerDone()
      ..finishPause()
      ..grade(ok: true)
      ..finishPause()
      ..grade(ok: false);
    expect(s.prompt!.line.index, 2);
    expect(s.current!.line.index, 4);
    // A walk that starts on my line has nothing to replay.
    final first = RehearsalSession(
      _scene1(const LineRange(2, 5)),
      selfGrade: true,
    )..finishPause();
    first.grade(ok: false);
    expect(first.phase, Phase.mine);
    expect(first.current!.line.index, 2);
    expect(first.prompt, isNull);
  });

  test('skip leaves the retry; back keeps the first attempt', () {
    final s = RehearsalSession(_scene1(), selfGrade: true)
      ..partnerDone()
      ..finishPause()
      ..grade(ok: false)
      ..skip();
    expect(s.current!.line.index, 4);
    expect(s.phase, Phase.mine);
    expect(s.results, {1: false});
    s.back();
    expect(s.current!.line.index, 2);
    s.finishPause();
    expect(s.grade(ok: true), isFalse);
    expect(s.results, {1: false});
  });

  test('scores count first attempts; a pure pass needs every first ✓', () {
    final s = RehearsalSession(_scene1(), loop: true, cleanTarget: 1);
    _pass(s, [
      [false, false, true],
      [true],
    ]);
    expect(s.history.last.toString(), '1/2');
    expect(s.purePasses, 0);
    expect(s.pass, 2);
    _pass(s, [
      [true],
      [true],
    ]);
    expect(s.phase, Phase.finished);
    expect(s.purePasses, 1);
  });

  test('no pure pass without grading, own lines, or the whole walk', () {
    final plain = RehearsalSession(_scene1());
    _pass(plain, []);
    expect(plain.history.single.clean, isTrue);
    expect(plain.purePasses, 0);
    final none = RehearsalSession(
      buildCues(fixtureScript(), const {}, const LineRange(1, 1)),
      selfGrade: true,
    )..partnerDone();
    expect(none.phase, Phase.finished);
    expect(none.purePasses, 0);
    // Resumed past my first line: it was never tried in this pass.
    final resumed = RehearsalSession(_scene1(), selfGrade: true, startAt: 2);
    _pass(resumed, [
      [true],
    ]);
    expect(resumed.phase, Phase.finished);
    expect(resumed.purePasses, 0);
  });
}
