import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/session.dart';

import 'controller_test.dart' show FakePlayer;
import 'fake_capture.dart';
import 'fixture.dart';

RehearsalController _make(FakeCapture? mic, {int startAt = 0}) {
  final s = fixtureScript();
  final cues = buildCues(
    s,
    {const Role.character(wolf)},
    LineRange.section(s.scenes[0]),
    overrides: const {2: 3, 4: 1},
  );
  return RehearsalController(
    RehearsalSession(cues, selfGrade: true, startAt: startAt),
    FakePlayer(),
    capture: mic,
  );
}

void main() {
  test('end of speech ends my line and suggests ✓ from the transcript', () {
    fakeAsync((fa) {
      final mic = FakeCapture();
      final c = _make(mic, startAt: 1)..start();
      expect(c.session.phase, Phase.mine);
      expect(mic.listening, isTrue);
      mic.hear(take(2, 'Piaskowe wilki nie jedzą krasnali'));
      fa.flushMicrotasks();
      expect(c.session.phase, Phase.grade);
      expect(c.heard, 'Piaskowe wilki nie jedzą krasnali');
      expect(c.suggestion, isTrue);
      c.grade(ok: true);
      // Next own line: a wrong transcript suggests ✗.
      expect(c.suggestion, isNull);
      mic.hear(take(1, 'zupełnie nie to'));
      fa.flushMicrotasks();
      expect(c.suggestion, isFalse);
      c.dispose();
    });
  });

  test('"done" before silence keeps listening\'s result for the grade', () {
    fakeAsync((fa) {
      final mic = FakeCapture()..onFinish = take(1, 'Naprawdę');
      final c = _make(mic, startAt: 2)..start();
      expect(c.session.current!.line.index, 4);
      c.done();
      fa.flushMicrotasks();
      expect(c.session.phase, Phase.grade);
      expect(c.suggestion, isTrue);
      c.dispose();
    });
  });

  test('no recognizer: the line still ends, nothing is suggested', () {
    fakeAsync((fa) {
      final mic = FakeCapture();
      final c = _make(mic, startAt: 1)..start();
      mic.hear(take(2));
      fa.flushMicrotasks();
      expect(c.session.phase, Phase.grade);
      expect(c.suggestion, isNull);
      c.dispose();
    });
  });

  test('skipping away cancels listening', () {
    fakeAsync((fa) {
      final mic = FakeCapture();
      final c = _make(mic, startAt: 1)..start();
      c.skip();
      fa.flushMicrotasks();
      expect(mic.listens, 2); // the next own line listens again
      expect(c.session.current!.line.index, 4);
      c.dispose();
    });
  });

  test('−/+ change the pause and the running countdown', () {
    fakeAsync((fa) {
      final c = _make(null, startAt: 1)..start();
      expect(c.remaining, closeTo(3, 0.01));
      fa.elapse(const Duration(seconds: 1));
      expect(c.adjustPause(0.5), 3.5);
      expect(c.session.current!.seconds, 3.5);
      expect(c.remaining, closeTo(2.5, 0.11));
      expect(c.adjustPause(-0.5), 3);
      for (var i = 0; i < 10; i++) {
        c.adjustPause(-0.5);
      }
      expect(c.session.current!.seconds, RehearsalController.minPause);
      expect(c.remaining, greaterThan(0));
      fa.elapse(const Duration(seconds: 1));
      expect(c.session.phase, Phase.grade);
      // Still adjustable while grading (it was too short).
      expect(c.adjustPause(1), 1.5);
      c.dispose();
    });
  });
}
