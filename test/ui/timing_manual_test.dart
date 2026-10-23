import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};

const _first = 'Piaskowe Wilki nie jedzą Krasnali!';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<TestRig> _walk(WidgetTester tester, String db) async {
  tester.usePhone();
  final rig = await openHub(
    tester,
    db,
    roles: _wolf,
    // Line 2 already has a recording; a tapped time must not replace it.
    seed: (rig) async {
      await rig.library.saveRecording(
        rig.script.id,
        2,
        pcmToWav(Uint8List(16000), sampleRate: 16000),
      );
    },
  );
  await tester.tap(find.byTooltip('Nagraj czasy: Scena 1'));
  await _settle(tester);
  return rig;
}

void main() {
  testWidgets('mic not heard: "Skończyłem" times the line, walk goes on', (
    tester,
  ) async {
    final rig = await _walk(tester, 'rec-manual');
    expect(find.text('Kwestia 1/2'), findsOneWidget);
    rig.capture.hear(null);
    await _settle(tester);
    expect(find.textContaining('Nie słyszę mikrofonu'), findsOneWidget);
    // Own text hidden: said from memory, timed by the tap.
    expect(find.text(_first), findsNothing);
    final done = find.widgetWithText(FilledButton, 'Skończyłem');
    expect(done, findsOneWidget);
    expect(tester.getSize(done).height, greaterThanOrEqualTo(72));
    await tester.tap(done);
    await _settle(tester);
    expect(find.text('Kwestia 2/2'), findsOneWidget);
    expect(find.text('Naprawdę.'), findsOneWidget);
    expect(rig.capture.listening, isTrue);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds.keys, [2]);
    expect(prefs.recordings.keys, [2]);
    await tester.tap(find.text('Stop'));
    await _settle(tester);
    expect(find.text('Gotowe: zapisano 1 z 2'), findsOneWidget);
  });

  testWidgets('"Bez mikrofonu" times the whole walk by taps', (tester) async {
    final rig = await _walk(tester, 'rec-nomic');
    expect(rig.capture.listening, isTrue);
    await tester.tap(find.byKey(const Key('manual-walk')));
    await _settle(tester);
    expect(rig.capture.listening, isFalse);
    expect(find.textContaining('Nie słyszę mikrofonu'), findsNothing);
    expect(find.text(_first), findsNothing);
    await tester.tap(find.text('Skończyłem'));
    await _settle(tester);
    expect(find.text('Kwestia 2/2'), findsOneWidget);
    expect(find.text('Naprawdę.'), findsNothing);
    expect(rig.capture.listening, isFalse);
    await tester.tap(find.text('Skończyłem'));
    await _settle(tester);
    expect(find.text('Gotowe: zapisano 2 z 2'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds.keys, unorderedEquals([2, 4]));
    expect(prefs.recordings.keys, [2]);
    expect(rig.capture.listens, 1);
  });
}
