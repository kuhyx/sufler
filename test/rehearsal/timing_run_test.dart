import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/run_take.dart';
import 'package:sufler/rehearsal/runs.dart';
import 'package:sufler/rehearsal/timing_session.dart';
import 'package:sufler/rehearsal/wav.dart';

import 'fake_capture.dart';
import 'run_fixture.dart';

/// [loud] seconds of tone after [before] s of silence, then 0.5 s quiet.
Uint8List _tone({double before = 1, double loud = 6}) {
  const rate = 16000;
  final n = ((before + loud + 0.5) * rate).round();
  final pcm = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final on = t >= before && t < before + loud;
    pcm.setInt16(
      i * 2,
      on ? (math.sin(2 * math.pi * 300 * t) * 9000).round() : 0,
      Endian.little,
    );
  }
  return pcmToWav(pcm.buffer.asUint8List(), sampleRate: rate);
}

class _Mic {
  bool allow = true;
  bool recording = false;
  Uint8List? wav = _tone();
  Transcript? heard;
  int transcribed = 0;

  RunMic get mic => RunMic(
    start: () async => recording = allow,
    stop: () async {
      recording = false;
      return wav;
    },
    transcribe: (w) async {
      transcribed++;
      return heard;
    },
  );
}

typedef _Rig = ({
  TimingSession session,
  FakeCapture capture,
  _Mic mic,
  Map<int, CaptureResult> saved,
});

_Rig _rig({Set<int> recorded = const {}}) {
  final script = runScript();
  final roles = {const Role.character(wolf)};
  final lines = [
    for (final l in script.lines)
      if (isMine(l, roles)) l,
  ];
  final capture = FakeCapture();
  final mic = _Mic();
  final saved = <int, CaptureResult>{};
  final session = TimingSession(
    lines: lines,
    capture: capture,
    save: (line, t) async => saved[line.index] = t,
    saveTime: (line, s) async {},
    whole: WholeRuns(
      runs: findRuns(script, roles),
      mic: mic.mic,
      hasRecording: (l) async => recorded.contains(l.index),
    ),
  );
  return (session: session, capture: capture, mic: mic, saved: saved);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a run start offers the whole run; other lines do not', () async {
    final r = _rig();
    final walk = r.session.run();
    await _settle();
    expect(r.session.current!.index, 2);
    expect(r.session.runHere, 3);
    r.capture.hear(take(1));
    await _settle();
    expect(r.session.current!.index, 4);
    expect(r.session.runHere, 0, reason: 'only offered at its first line');
    await r.session.stop();
    await walk;
  });

  test('one take for the run: split by syllables, a slice per line', () async {
    final r = _rig();
    final walk = r.session.run();
    await _settle();
    r.session.recordRun();
    await _settle();
    expect(r.session.state, TakeState.run);
    expect(r.capture.listening, isFalse, reason: 'mic released');
    expect(r.mic.recording, isTrue);
    expect([for (final l in r.session.runLines!) l.index], [2, 4, 5]);
    r.session.finished();
    await _settle();
    // No transcript: 5 + 2 + 8 syllables over the tone (1..7 s).
    expect(r.saved.keys, [2, 4, 5]);
    expect(r.saved[2]!.speechStart, closeTo(1, 0.05));
    expect(r.saved[2]!.durationSeconds, closeTo(6 * 5 / 15, 0.05));
    expect(r.saved[4]!.durationSeconds, closeTo(6 * 2 / 15, 0.05));
    expect(r.saved[5]!.speechEnd, closeTo(7, 0.05));
    expect(
      wavSeconds(r.saved[4]!.audio!),
      closeTo(r.saved[4]!.durationSeconds, 0.01),
    );
    expect(r.session.state, TakeState.listening);
    expect(r.session.current!.index, 7);
    expect(r.session.saved, 3);
    expect(r.session.runNote, 'Zapisano w całości: 3 kwestie');
    await r.session.stop();
    await walk;
  });

  test('desktop: heard words cut the lines', () async {
    final r = _rig();
    r.mic.heard = (
      text: 'raz dwa trzy cztery pięć sześć siedem osiem dziewięć dziesięć',
      speechStart: 1.0,
      speechEnd: 7.0,
      words: [
        for (final (i, w)
            in 'raz dwa trzy cztery pięć sześć siedem osiem '
                    'dziewięć dziesięć'
                .split(' ')
                .indexed)
          (text: w, start: 1 + i * 0.6, end: 1 + i * 0.6 + 0.5),
      ],
    );
    final walk = r.session.run();
    await _settle();
    r.session.recordRun();
    await _settle();
    r.session.finished();
    await _settle();
    expect(r.mic.transcribed, 1);
    expect(r.saved[2]!.speechStart, closeTo(1, 1e-9));
    expect(r.saved[2]!.speechEnd, closeTo(3.3, 1e-9));
    expect(r.saved[4]!.speechStart, closeTo(3.4, 1e-9));
    expect(r.saved[5]!.speechEnd, closeTo(6.9, 1e-9));
    await r.session.stop();
    await walk;
  });

  test(
    'existing recordings: asked first, kept when the user says so',
    () async {
      final r = _rig(recorded: {4});
      final walk = r.session.run();
      await _settle();
      r.session.recordRun();
      await _settle();
      r.session.finished();
      await _settle();
      expect(r.session.state, TakeState.overwrite);
      expect(r.session.runExisting, 1);
      expect(r.saved, isEmpty, reason: 'nothing written before the answer');
      r.session.overwrite(yes: false);
      await _settle();
      expect(r.saved.keys, [2, 5]);
      expect(r.session.current!.index, 7);
      await r.session.stop();
      await walk;
    },
  );

  test('…or overwritten', () async {
    final r = _rig(recorded: {2, 4, 5});
    final walk = r.session.run();
    await _settle();
    r.session.recordRun();
    await _settle();
    r.session.finished();
    await _settle();
    r.session.overwrite(yes: true);
    await _settle();
    expect(r.saved.keys, [2, 4, 5]);
    await r.session.stop();
    await walk;
  });

  test('no mic: back to line by line at the same line', () async {
    final r = _rig();
    r.mic.allow = false;
    final walk = r.session.run();
    await _settle();
    r.session.recordRun();
    await _settle();
    expect(r.session.state, TakeState.listening);
    expect(r.session.current!.index, 2);
    expect(r.session.runNote, 'Nie nagrano w całości: brak mikrofonu');
    await r.session.stop();
    await walk;
  });

  test('stop during the run saves nothing', () async {
    final r = _rig();
    final walk = r.session.run();
    await _settle();
    r.session.recordRun();
    await _settle();
    await r.session.stop();
    await walk;
    expect(r.saved, isEmpty);
    expect(r.mic.recording, isFalse);
    expect(r.session.state, TakeState.done);
  });
}
