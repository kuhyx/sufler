import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/timing_session.dart';

import 'fake_capture.dart';

ScriptLine _line(int i, String text) => ScriptLine(
  index: i,
  speakers: const ['a'],
  text: text,
  kind: LineKind.dialogue,
);

final _lines = [
  _line(2, 'Pierwsza kwestia tutaj'),
  _line(4, 'Druga kwestia jest dłuższa'),
  _line(7, 'Trzecia i ostatnia kwestia'),
];

class _Rig {
  _Rig({bool manual = false}) {
    session = TimingSession(
      lines: _lines,
      capture: mic,
      save: (line, t) async => takes[line.index] = t,
      saveTime: (line, s) async => times[line.index] = s,
      clock: () => now,
      manual: manual,
    );
  }

  final mic = FakeCapture();
  final takes = <int, CaptureResult>{};
  final times = <int, double>{};
  DateTime now = DateTime(2026, 10, 23, 18, 40);
  late final TimingSession session;

  void wait(double seconds) =>
      now = now.add(Duration(milliseconds: (seconds * 1000).round()));
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'a take the mic missed turns the line manual; the walk goes on',
    () async {
      final r = _Rig();
      final run = r.session.run();
      await _settle();
      r.wait(2);
      r.mic.hear(null);
      await _settle();
      expect(r.session.state, TakeState.manual);
      expect(r.session.problem, 'Nie słyszę mikrofonu');
      expect(r.session.current!.index, 2);
      // The time runs from when the line was shown, listening included.
      r.wait(1.24);
      r.session.finished();
      await _settle();
      expect(r.times, {2: 3.2});
      expect(r.takes, isEmpty);
      expect(r.session.lastPause, 3.2);
      expect(r.session.saved, 1);
      expect(r.session.position, 1);
      expect(r.session.state, TakeState.listening);
      expect(r.session.problem, isNull);
      expect(r.mic.listens, 2);
      r.mic.hear(take(2));
      await _settle();
      expect(r.takes.keys, [4]);
      await r.session.stop();
      await run;
    },
  );

  test('an empty take (no speech, no words) is handled the same', () async {
    final r = _Rig();
    final run = r.session.run();
    await _settle();
    r.mic.hear(
      const CaptureResult(speechStart: 0, speechEnd: 0, transcript: ''),
    );
    await _settle();
    expect(r.session.state, TakeState.manual);
    await r.session.stop();
    await run;
    expect(r.takes, isEmpty);
  });

  test('sound but no words is still a take with its timing', () async {
    final r = _Rig();
    final run = r.session.run();
    await _settle();
    r.mic.hear(take(1.5, ''));
    await _settle();
    expect(r.takes[2]!.durationSeconds, 1.5);
    expect(r.session.state, TakeState.listening);
    await r.session.stop();
    await run;
  });

  test('manual from the start: no mic, each tap times a line', () async {
    final r = _Rig(manual: true);
    final run = r.session.run();
    await _settle();
    expect(r.session.manualAll, isTrue);
    expect(r.session.state, TakeState.manual);
    expect(r.session.problem, isNull);
    for (final s in [1.5, 2.04, 0.66]) {
      r.wait(s);
      r.session.finished();
      await _settle();
    }
    await run;
    expect(r.mic.listens, 0);
    // Rounded to 0.1 s.
    expect(r.times, {2: 1.5, 4: 2.0, 7: 0.7});
    expect(r.session.saved, 3);
    expect(r.session.state, TakeState.done);
  });

  test('a double tap does not time the next line too', () async {
    final r = _Rig(manual: true);
    final run = r.session.run();
    await _settle();
    r.wait(2);
    r.session.finished();
    await _settle();
    // The button stays put: a bounce 0.15 s later is not line 4 done.
    r.wait(0.15);
    r.session.finished();
    await _settle();
    expect(r.times, {2: 2.0});
    expect(r.session.current!.index, 4);
    r.wait(1.85);
    r.session.finished();
    await _settle();
    expect(r.times, {2: 2.0, 4: 2.0});
    await r.session.stop();
    await run;
  });

  test(
    'switching to manual mid-listen cancels the take, no mic warning',
    () async {
      final r = _Rig();
      final run = r.session.run();
      await _settle();
      expect(r.mic.listening, isTrue);
      r.wait(1);
      r.session.setManual(on: true);
      await _settle();
      expect(r.mic.listening, isFalse);
      expect(r.session.state, TakeState.manual);
      expect(r.session.problem, isNull);
      expect(r.session.current!.index, 2);
      r.wait(1.5);
      r.session.finished();
      await _settle();
      expect(r.times, {2: 2.5});
      expect(r.session.state, TakeState.manual);
      expect(r.mic.listens, 1);
      // And back to the mic from the next line on.
      r.session.setManual(on: false);
      r.wait(1);
      r.session.finished();
      await _settle();
      expect(r.session.state, TakeState.listening);
      expect(r.mic.listens, 2);
      await r.session.stop();
      await run;
      expect(r.takes, isEmpty);
    },
  );

  test('Stop while waiting for the tap saves nothing', () async {
    final r = _Rig();
    final run = r.session.run();
    await _settle();
    r.mic.hear(null);
    await _settle();
    expect(r.session.state, TakeState.manual);
    r.wait(3);
    await r.session.stop();
    await run;
    r.session.finished();
    expect(r.times, isEmpty);
    expect(r.session.state, TakeState.done);
    expect(r.session.saved, 0);
  });

  test('dispose while waiting for the tap ends the walk', () async {
    final r = _Rig(manual: true);
    final run = r.session.run();
    await _settle();
    r.session.dispose();
    await run.timeout(const Duration(seconds: 1));
    expect(r.times, isEmpty);
  });
}
