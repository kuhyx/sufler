import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';
import 'no_words.dart';
import 'sections_nav.dart';

final _wolf = {const Role.character(wolf)};

const _first = 'Piaskowe Wilki nie jedzą Krasnali!';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Lets real time pass the tap guard (DateTime.now is not faked), then
/// taps "Skończyłem".
Future<void> _finish(WidgetTester t, [Finder? button]) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await t.tap(button ?? bySpoken('Skończyłem'));
  await _settle(t);
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
  await openSectionDetails(tester, 'Scena 1');
  await tester.tap(bySpoken('Nagraj czasy: Scena 1'));
  await _settle(tester);
  return rig;
}

void main() {
  testWidgets('mic not heard: "Skończyłem" times the line, walk goes on', (
    tester,
  ) async {
    final rig = await _walk(tester, 'rec-manual');
    expect(bySpoken('Kwestia 1/2'), findsOneWidget);
    rig.capture.hear(null);
    await _settle(tester);
    expect(bySpoken('Nie słyszę mikrofonu'), findsOneWidget);
    expectNoWords('timing walk, mic not heard', scriptContent(rig.script));
    // Own text hidden: said from memory, timed by the tap.
    expect(find.text(_first), findsNothing);
    final done = bySpoken('Skończyłem');
    expect(done, findsOneWidget);
    final button = find.ancestor(
      of: done,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.getSize(button.first).height, greaterThanOrEqualTo(72));
    await _finish(tester, done);
    expect(bySpoken('Kwestia 2/2'), findsOneWidget);
    expectNoWords('timing walk, line saved', scriptContent(rig.script));
    expect(find.text('Naprawdę.'), findsOneWidget);
    expect(rig.capture.listening, isTrue);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds.keys, [2]);
    expect(prefs.recordings.keys, [2]);
    await tester.tap(bySpoken('Stop'));
    await _settle(tester);
    expect(bySpoken('Gotowe: zapisano 1 z 2'), findsOneWidget);
    expectNoWords('timing walk done', scriptContent(rig.script));
  });

  testWidgets('"Bez mikrofonu" times the whole walk by taps', (tester) async {
    final rig = await _walk(tester, 'rec-nomic');
    expect(rig.capture.listening, isTrue);
    await tester.tap(find.byKey(const Key('manual-walk')));
    await _settle(tester);
    expect(rig.capture.listening, isFalse);
    expect(bySpokenContaining('Nie słyszę mikrofonu'), findsNothing);
    expect(find.text(_first), findsNothing);
    await _finish(tester);
    expect(bySpoken('Kwestia 2/2'), findsOneWidget);
    expect(find.text('Naprawdę.'), findsNothing);
    expect(rig.capture.listening, isFalse);
    await _finish(tester);
    expect(bySpoken('Gotowe: zapisano 2 z 2'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds.keys, unorderedEquals([2, 4]));
    expect(prefs.recordings.keys, [2]);
    expect(rig.capture.listens, 1);
  });
}
