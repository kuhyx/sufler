import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/controller.dart';
import 'package:sufler/rehearsal/cues.dart';
import 'package:sufler/rehearsal/range.dart';
import 'package:sufler/rehearsal/session.dart';

import 'fixture.dart';

/// Partner lines "play" for [seconds] of fake time.
class FakePlayer implements LinePlayer {
  FakePlayer({this.seconds = 2, this.fail = false});
  final double seconds;
  final bool fail;
  final played = <int>[];
  int stops = 0;

  @override
  Future<void> play(ScriptLine line) {
    played.add(line.index);
    if (fail) return Future.error(StateError('no tts'));
    return Future.delayed(Duration(milliseconds: (seconds * 1000).round()));
  }

  @override
  Future<void> stop() async => stops++;
}

RehearsalController _make(FakePlayer p, {bool selfGrade = false}) {
  final s = fixtureScript();
  final cues = buildCues(
    s,
    {const Role.character(wolf)},
    LineRange.section(s.scenes[0]),
    overrides: const {2: 3, 4: 1},
  );
  return RehearsalController(RehearsalSession(cues, selfGrade: selfGrade), p);
}

void main() {
  test('plays partner, counts down my pause, then advances', () {
    fakeAsync((fa) {
      final p = FakePlayer();
      final c = _make(p)..start();
      expect(c.session.phase, Phase.partner);
      expect(p.played, [1]);
      fa.elapse(const Duration(seconds: 2));
      expect(c.session.phase, Phase.mine);
      expect(c.remaining, closeTo(3, 0.01));
      fa.elapse(const Duration(milliseconds: 1500));
      expect(c.remaining, closeTo(1.5, 0.11));
      fa.elapse(const Duration(milliseconds: 1600));
      expect(c.session.current!.line.index, 4);
      fa.elapse(const Duration(milliseconds: 1100));
      expect(c.session.current!.line.index, 5);
      expect(p.played, [1, 5]);
      fa.elapse(const Duration(seconds: 3));
      expect(c.session.phase, Phase.finished);
      c.dispose();
    });
  });

  test('done ends my pause early; grade advances', () {
    fakeAsync((fa) {
      final c = _make(FakePlayer(), selfGrade: true)..start();
      fa.elapse(const Duration(seconds: 2));
      c.done();
      expect(c.session.phase, Phase.grade);
      c.grade(ok: true);
      expect(c.session.current!.line.index, 4);
      c.dispose();
    });
  });

  test('pause freezes countdown and stops audio; resume continues', () {
    fakeAsync((fa) {
      final p = FakePlayer();
      final c = _make(p)..start();
      fa.elapse(const Duration(seconds: 2, milliseconds: 1000));
      c.pause();
      expect(c.paused, isTrue);
      final left = c.remaining;
      fa.elapse(const Duration(seconds: 10));
      expect(c.remaining, left);
      expect(c.session.current!.line.index, 2);
      c.resume();
      fa.elapse(const Duration(milliseconds: 2100));
      expect(c.session.current!.line.index, 4);
      c.dispose();
    });
  });

  test('pause during partner line replays it on resume', () {
    fakeAsync((fa) {
      final p = FakePlayer();
      final c = _make(p)..start();
      fa.elapse(const Duration(seconds: 1));
      c.pause();
      fa.elapse(const Duration(seconds: 5));
      expect(c.session.current!.line.index, 1);
      c
        ..resume()
        ..resume(); // second resume is a no-op
      expect(p.played, [1, 1]);
      fa.elapse(const Duration(seconds: 2));
      expect(c.session.phase, Phase.mine);
      c.dispose();
    });
  });

  test('skip and back interrupt audio; stale completion is ignored', () {
    fakeAsync((fa) {
      final p = FakePlayer();
      final c = _make(p)..start();
      c.skip();
      expect(c.session.current!.line.index, 2);
      expect(p.stops, greaterThan(0));
      fa.elapse(const Duration(seconds: 2)); // old partner future completes
      expect(c.session.current!.line.index, 2);
      c.back();
      expect(c.session.current!.line.index, 1);
      c.restart();
      expect(c.session.position, 0);
      c.dispose();
    });
  });

  test('a failing player still advances', () {
    fakeAsync((fa) {
      final c = _make(FakePlayer(fail: true))..start();
      fa.flushMicrotasks();
      expect(c.session.phase, Phase.mine);
      c.dispose();
    });
  });

  test('✗ replays the cue before through the player, then asks again', () {
    fakeAsync((fa) {
      final p = FakePlayer();
      final c = _make(p, selfGrade: true)..start();
      fa.elapse(const Duration(seconds: 2));
      c.done();
      expect(c.grade(ok: false), isTrue);
      expect(c.session.phase, Phase.prompt);
      expect(p.played, [1, 1]);
      // Pause during the replay; resume plays it again.
      c.pause();
      fa.elapse(const Duration(seconds: 5));
      c.resume();
      expect(p.played, [1, 1, 1]);
      fa.elapse(const Duration(seconds: 2));
      expect(c.session.phase, Phase.mine);
      expect(c.session.current!.line.index, 2);
      expect(c.remaining, closeTo(3, 0.01));
      c.done();
      expect(c.grade(ok: true), isFalse);
      expect(c.session.current!.line.index, 4);
      c.dispose();
    });
  });

  test('notifies listeners on every change', () {
    fakeAsync((fa) {
      final c = _make(FakePlayer());
      var n = 0;
      c
        ..addListener(() => n++)
        ..start();
      fa.elapse(const Duration(seconds: 3));
      expect(n, greaterThan(3));
      c.dispose();
    });
  });
}
