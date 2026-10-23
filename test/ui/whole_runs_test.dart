import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/prefs.dart';

import '../rehearsal/fixture.dart' show fixtureScript;
import '../rehearsal/run_fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _first = 'Raz dwa trzy cztery.';
const _last = 'Siedem osiem dziewięć dziesięć.';

Future<void> _speakDone(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 6 s of tone after 1 s of silence.
Uint8List _take() {
  const rate = 16000;
  final pcm = ByteData(rate * 8 * 2);
  for (var i = 0; i < rate * 8; i++) {
    final t = i / rate;
    final on = t >= 1 && t < 7;
    pcm.setInt16(
      i * 2,
      on ? (math.sin(2 * math.pi * 300 * t) * 9000).round() : 0,
      Endian.little,
    );
  }
  return pcmToWav(pcm.buffer.asUint8List(), sampleRate: rate);
}

Future<TestRig> _hub(
  WidgetTester tester,
  String db, {
  AppSettings settings = const AppSettings(),
  Future<void> Function(TestRig rig)? seed,
}) {
  tester.usePhone();
  return openHub(
    tester,
    db,
    roles: _wolf,
    script: runScript(),
    settings: settings,
    seed: seed,
  );
}

void main() {
  testWidgets('settings: "Piosenki i monologi w całości" is on, can go off', (
    tester,
  ) async {
    final rig = await _hub(tester, 'runs-setting');
    await openTab(tester, 'Ustawienia próby');
    final toggle = find.byKey(const Key('whole-runs'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tapVisible(toggle);
    final s = await tester.io(() => rig.library.loadSettings());
    expect(s.wholeRuns, isFalse);
  });

  testWidgets('learn: the monologue is said whole, graded once, retried', (
    tester,
  ) async {
    final rig = await _hub(tester, 'runs-learn');
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.textContaining(_first), findsNothing);
    expect(find.byKey(const Key('pause')), findsNothing);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text('Jak poszło?'), findsOneWidget);
    expect(find.text('$_first\nPięć sześć.\n$_last'), findsOneWidget);
    await tester.tap(find.text('Źle'));
    await tester.pump();
    expect(rig.speech.said, [
      'Witaj, Wilku.',
      'Witaj, Wilku.',
    ], reason: 'cue replayed');
    await _speakDone(tester);
    expect(find.byKey(const Key('retry')), findsOneWidget);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    expect(rig.speech.said.last, 'Brawo.');
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('run123'));
    expect(prefs.knowledge, {
      2: [false],
      4: [false],
      5: [false],
    });
  });

  testWidgets('learn with the setting off: line by line', (tester) async {
    await _hub(
      tester,
      'runs-off',
      settings: const AppSettings(wholeRuns: false),
    );
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text(_first), findsOneWidget);
    expect(find.textContaining(_last), findsNothing);
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text('Pięć sześć.'), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('timing walk: "Nagraj w całości" saves a slice per line', (
    tester,
  ) async {
    final rig = await _hub(tester, 'runs-rec');
    rig.recorder.result = _take();
    await tester.tap(find.byTooltip('Nagraj czasy: Scena 1'));
    await _settle(tester);
    expect(find.text('Kwestia 1/7'), findsOneWidget);
    await tester.tap(find.text('Nagraj w całości (3 kwestie)'));
    await _settle(tester);
    expect(rig.recorder.recording, isTrue);
    expect(find.text('$_first\nPięć sześć.\n$_last'), findsOneWidget);
    await tester.tap(find.text('Skończyłem'));
    await _settle(tester);
    expect(find.text('Zapisano w całości: 3 kwestie'), findsOneWidget);
    expect(find.text('Kwestia 4/7'), findsOneWidget);
    expect(find.text('Teraz piosenka.'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('run123'));
    expect(prefs.recordings.keys, [2, 4, 5]);
    await tester.tap(find.text('Stop'));
    await _settle(tester);
  });

  testWidgets('timing walk: an existing recording is only replaced on ask', (
    tester,
  ) async {
    final old = pcmToWav(Uint8List(3200), sampleRate: 16000);
    final rig = await _hub(
      tester,
      'runs-keep',
      seed: (rig) => rig.library.saveRecording('run123', 4, old),
    );
    rig.recorder.result = _take();
    await tester.tap(find.byTooltip('Nagraj czasy: Scena 1'));
    await _settle(tester);
    await tester.tap(find.text('Nagraj w całości (3 kwestie)'));
    await _settle(tester);
    await tester.tap(find.text('Skończyłem'));
    await _settle(tester);
    expect(find.text('1 z tych kwestii ma już nagranie.'), findsOneWidget);
    await tester.tap(find.text('Zachowaj istniejące'));
    await _settle(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('run123'));
    expect(prefs.recordings.keys.toSet(), {2, 4, 5});
    final kept = await tester.io(
      () => rig.library.loadRecording(prefs.recordings[4]!),
    );
    expect(kept, old);
    await tester.tap(find.text('Stop'));
    await _settle(tester);
  });

  testWidgets('a partner song is one step: all verses, then my line', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'runs-partner',
      roles: _wolf,
      script: fixtureScript(),
    );
    await tester.tapVisible(find.text('Scena 2'));
    String header() =>
        tester.widget<Text>(find.textContaining('Przebieg').first).data!;
    expect(header(), contains('kwestia 1/2'));
    expect(find.text('Chór, Błystek · Piosenka'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(header(), contains('kwestia 1/2'), reason: 'still singing');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(rig.speech.said, ['La la la', 'Śpiewam ja', 'Hej hej']);
    expect(header(), contains('kwestia 2/2'));
    expect(find.text('Twoja kwestia'), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('a resume point saved line by line lands on the same line', (
    tester,
  ) async {
    // Saved before runs: cue 5 of the unfolded walk is line 7.
    final rig = await _hub(
      tester,
      'runs-resume',
      seed: (rig) => rig.library.updatePrefs(
        'run123',
        (p) => p.copyWith(
          resume: const ResumePoint(label: 'Scena 1', start: 0, end: 11).at(5),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('learn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    String header() =>
        tester.widget<Text>(find.textContaining('Przebieg').first).data!;
    expect(header(), contains('kwestia 4/6'));
    expect(find.text('Twoja kwestia'), findsOneWidget);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('run123'));
    expect(prefs.resume!.position, 4);
    expect(prefs.resume!.line, 8, reason: 'the song, by its first line');
  });
}
