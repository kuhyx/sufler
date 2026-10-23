import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/session.dart';

import 'fixture.dart';

// Scene 1 for the wolf: 1 partner, 2 mine, 4 mine, 5 partner.
List<Cue> _scene1() {
  final s = fixtureScript();
  return buildCues(s, {
    const Role.character(wolf),
  }, LineRange.section(s.scenes[0]));
}

/// Plays one whole pass, grading own lines with [grades] in order.
void _pass(RehearsalSession s, List<bool> grades) {
  final g = [...grades];
  while (s.phase != Phase.finished) {
    final startPass = s.pass;
    switch (s.phase) {
      case Phase.partner:
        s.partnerDone();
      case Phase.mine:
        s.finishPause();
      case Phase.grade:
        s.grade(ok: g.removeAt(0));
      case Phase.finished:
        break;
    }
    if (s.pass != startPass) return;
  }
}

void main() {
  test('single pass without grading walks partner/mine/mine/partner', () {
    final s = RehearsalSession(_scene1());
    final seen = <(int, Phase)>[];
    while (s.phase != Phase.finished) {
      seen.add((s.current!.line.index, s.phase));
      s.phase == Phase.partner ? s.partnerDone() : s.finishPause();
    }
    expect(seen, [
      (1, Phase.partner),
      (2, Phase.mine),
      (4, Phase.mine),
      (5, Phase.partner),
    ]);
    expect(s.current, isNull);
    expect(s.history.single.total, 2);
  });

  test('self-grade inserts a grade step after each own line', () {
    final s = RehearsalSession(_scene1(), selfGrade: true)..partnerDone();
    expect(s.phase, Phase.mine);
    s.finishPause();
    expect(s.phase, Phase.grade);
    s.grade(ok: true);
    expect(s.current!.line.index, 4);
    expect(s.results, {1: true});
  });

  test('loop repeats until N consecutive clean passes, with scores', () {
    final s = RehearsalSession(_scene1(), loop: true, cleanTarget: 2);
    _pass(s, [true, false]);
    expect(s.pass, 2);
    expect(s.history.last.ok, 1);
    expect(s.history.last.clean, isFalse);
    expect(s.cleanStreak, 0);
    _pass(s, [true, true]);
    expect(s.cleanStreak, 1);
    _pass(s, [false, true]);
    expect(s.cleanStreak, 0);
    _pass(s, [true, true]);
    _pass(s, [true, true]);
    expect(s.phase, Phase.finished);
    expect(s.cleanStreak, 2);
    expect([for (final p in s.history) p.ok], [1, 2, 1, 2, 2]);
    expect(s.history.first.toString(), '1/2');
  });

  test('skip moves on; a skipped own line counts as missed', () {
    final s = RehearsalSession(_scene1(), loop: true, cleanTarget: 1)
      ..skip(); // partner 1
    expect(s.current!.line.index, 2);
    s
      ..skip() // my 2, missed
      ..finishPause()
      ..grade(ok: true)
      ..skip();
    expect(s.history.single.ok, 1);
    expect(s.history.single.clean, isFalse);
    expect(s.pass, 2);
  });

  test('back steps to the previous cue and clears its grade', () {
    final s = RehearsalSession(_scene1(), selfGrade: true)
      ..partnerDone()
      ..finishPause()
      ..grade(ok: false);
    expect(s.current!.line.index, 4);
    s.back();
    expect(s.current!.line.index, 2);
    expect(s.phase, Phase.mine);
    expect(s.results, isEmpty);
    s
      ..back()
      ..back(); // stays at the first cue
    expect(s.position, 0);
    expect(s.phase, Phase.partner);
  });

  test('back from finished returns to the last cue; restart resets', () {
    final s = RehearsalSession(_scene1());
    _pass(s, []);
    expect(s.phase, Phase.finished);
    s.back();
    expect(s.current!.line.index, 5);
    s.restart();
    expect(s.position, 0);
    expect(s.pass, 1);
    expect(s.history, isEmpty);
  });

  test('empty cue list is finished at once; finished ignores input', () {
    final s = RehearsalSession(const [])
      ..skip()
      ..partnerDone()
      ..finishPause()
      ..grade(ok: true);
    expect(s.phase, Phase.finished);
    expect(s.ownCount, 0);
  });

  test('a pass with no own lines is clean', () {
    final s = fixtureScript();
    final cues = buildCues(s, const {}, const LineRange(1, 1));
    final session = RehearsalSession(cues, loop: true, cleanTarget: 1)
      ..partnerDone();
    expect(session.phase, Phase.finished);
    expect(session.history.single.clean, isTrue);
  });
}
