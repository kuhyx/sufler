import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

Future<TestRig> _openTimings(WidgetTester tester, String db) async {
  tester.usePhone();
  final rig = await openHub(
    tester,
    db,
    roles: {const Role.character(wolf)},
    tab: 'Narzędzia',
  );
  await tester.tapVisible(find.text('Czasy i nagrania'));
  return rig;
}

void main() {
  testWidgets('manual pause override, then back to automatic', (tester) async {
    final rig = await _openTimings(tester, 'timing-manual');
    // Only my lines: 2, 4, 10.
    expect(find.text('Dzień dobry, Wilku!'), findsNothing);
    expect(find.textContaining('automatycznie'), findsNWidgets(3));

    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('seconds')), '9,5');
    await tester.tap(find.text('Ustaw pauzę'));
    await tester.pumpAndSettle();
    expect(find.text('Pauza 9,5 s · ręcznie'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds, {4: 9.5});

    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('seconds')), 'abc');
    await tester.tap(find.text('Ustaw pauzę'));
    await tester.pumpAndSettle();
    expect(find.text('Podaj liczbę sekund większą od zera'), findsOneWidget);
    await tester.tap(find.text('Automatycznie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('automatycznie'), findsNWidgets(3));
  });

  testWidgets('record me: pause = recording + 1 s, playback, delete', (
    tester,
  ) async {
    final rig = await _openTimings(tester, 'timing-rec');
    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nagraj mnie'));
    await tester.pumpAndSettle();
    expect(rig.recorder.recording, isTrue);
    rig.recorder.result = pcmToWav(Uint8List(48000), sampleRate: 16000);
    await tester.tap(find.text('Zatrzymaj nagrywanie'));
    await tester.pumpAndSettle();
    expect(find.text('Pauza 2,5 s · z nagrania'), findsOneWidget);
    // The recorded line's mic, besides the "Nagraj czasy" button.
    expect(find.byIcon(Icons.mic), findsNWidgets(2));

    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odtwórz nagranie'));
    await tester.pumpAndSettle();
    expect(rig.clips.played, ['audio/wav']);
    await tester.tap(find.text('Usuń nagranie'));
    await tester.pumpAndSettle();
    expect(find.textContaining('automatycznie'), findsNWidgets(3));
  });

  testWidgets('denied microphone shows an error', (tester) async {
    final rig = await _openTimings(tester, 'timing-denied');
    rig.recorder.allow = false;
    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nagraj mnie'));
    await tester.pumpAndSettle();
    expect(find.text('Brak dostępu do mikrofonu'), findsOneWidget);
  });
}
