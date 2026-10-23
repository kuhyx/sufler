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

({TimingSession session, FakeCapture mic, Map<int, CaptureResult> saved})
_rig() {
  final mic = FakeCapture();
  final saved = <int, CaptureResult>{};
  final session = TimingSession(
    lines: _lines,
    capture: mic,
    save: (line, t) async => saved[line.index] = t,
    saveTime: (line, s) async {},
  );
  return (session: session, mic: mic, saved: saved);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('one start walks every line and advances by itself', () async {
    final r = _rig();
    r.mic.queue.addAll([take(1.5), take(2), take(2.5)]);
    await r.session.run();
    expect(r.saved.keys, [2, 4, 7]);
    expect(r.saved[4]!.durationSeconds, 2);
    expect(r.session.saved, 3);
    expect(r.session.state, TakeState.done);
    expect(r.session.current, isNull);
  });

  test('stop ends the walk; the line being read is not saved', () async {
    final r = _rig();
    r.mic.queue.add(take(1));
    final run = r.session.run();
    await _settle();
    expect(r.session.position, 1);
    expect(r.session.current!.index, 4);
    expect(r.mic.listening, isTrue);
    await r.session.stop();
    await run;
    expect(r.saved.keys, [2]);
    expect(r.session.state, TakeState.done);
    expect(r.session.problem, isNull);
  });

  test('a skipped line is spotted: accept keeps the take there', () async {
    final r = _rig();
    final run = r.session.run();
    await _settle();
    r.mic.hear(take(2, 'druga kwestia jest dłuższa'));
    await _settle();
    expect(r.session.state, TakeState.skipped);
    expect(r.session.skipTo, 1);
    r.session.accept();
    await _settle();
    expect(r.saved.keys, [4]);
    expect(r.session.position, 2);
    r.mic.hear(take(1, 'trzecia i ostatnia kwestia'));
    await run;
    expect(r.saved.keys, [4, 7]);
  });

  test('redo listens to the same line again', () async {
    final r = _rig();
    final run = r.session.run();
    await _settle();
    r.mic.hear(take(2, 'trzecia i ostatnia kwestia'));
    await _settle();
    expect(r.session.skipTo, 2);
    r.session.redo();
    await _settle();
    expect(r.session.state, TakeState.listening);
    expect(r.session.position, 0);
    expect(r.mic.listens, 2);
    // A take that sounds like nothing in particular is kept as is.
    r.mic.hear(take(1, 'coś zupełnie innego'));
    await _settle();
    expect(r.saved.keys, [2]);
    await r.session.stop();
    await run;
  });

  test('no microphone no longer ends the walk: the line goes manual', () async {
    final r = _rig();
    r.mic.queue.add(null);
    final run = r.session.run();
    await _settle();
    expect(r.session.problem, 'Nie słyszę mikrofonu');
    expect(r.session.state, TakeState.manual);
    expect(r.saved, isEmpty);
    await r.session.stop();
    await run;
  });
}
