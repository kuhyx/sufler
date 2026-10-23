import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/prefs.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

Text _header(WidgetTester t) =>
    t.widget<Text>(find.textContaining('Przebieg').first);

Future<void> _speakDone(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
  await t.pump();
}

void main() {
  testWidgets('loop mode: grade, score per pass, finish after N clean', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'loop',
      roles: {const Role.character(wolf)},
      settings: const AppSettings(
        loop: true,
        cleanTarget: 1,
        visibility: TextVisibility.hide,
      ),
      seed: (rig) => rig.library.saveRecording(
        'abc123',
        2,
        pcmToWav(Uint8List(3200), sampleRate: 16000),
      ),
    );
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.text('Piaskowe Wilki nie jedzą Krasnali!'), findsNothing);

    // Pass 1: one right, one wrong -> not clean, loop again.
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text('Jak poszło?'), findsOneWidget);
    await tester.tap(find.byTooltip('Odtwórz moje nagranie'));
    await tester.pumpAndSettle(); // no countdown runs while grading
    expect(rig.clips.played, ['audio/wav']);
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Źle'));
    await tester.pump();
    // The prompt (my line before, hidden) is replayed; ✓ on the retry
    // does not lift the score.
    expect(find.text('(twoja kwestia)'), findsOneWidget);
    await _speakDone(tester);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    await _speakDone(tester);
    expect(_header(tester).data, contains('Przebieg 2'));
    expect(_header(tester).data, contains('ostatni wynik 1/2'));

    // Pause / resume during a partner line replays it.
    await tester.tap(find.byTooltip('Pauza'));
    await tester.pump();
    expect(find.byTooltip('Wznów'), findsOneWidget);
    await tester.tap(find.byTooltip('Wznów'));
    await _speakDone(tester);
    expect(find.text('Twoja kwestia'), findsOneWidget);

    // Back to the partner line, then skip it.
    await tester.tap(find.byTooltip('Wstecz'));
    await tester.pump();
    expect(find.text('Dzień dobry, Wilku!'), findsWidgets);
    await tester.tap(find.byTooltip('Dalej'));
    await tester.pump();

    // Pass 2 clean -> done.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Gotowe'));
      await tester.pump();
      await tester.tap(find.text('Dobrze'));
      await tester.pump();
    }
    await _speakDone(tester);
    expect(find.text('Koniec'), findsOneWidget);
    expect(find.textContaining('Umiesz to!'), findsOneWidget);
    expect(find.text('Przebieg 1: 1/2'), findsOneWidget);
    expect(find.text('Przebieg 2: 2/2'), findsOneWidget);

    await tester.tap(find.text('Jeszcze raz'));
    await tester.pump();
    expect(_header(tester).data, startsWith('Przebieg 1'));
    await leaveRehearsal(tester);
  });
}
