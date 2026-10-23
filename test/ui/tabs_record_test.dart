import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/wav.dart';

import '../rehearsal/fake_capture.dart';
import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('phone: bottom tabs for scenes, songs, settings, tools', (
    tester,
  ) async {
    tester.usePhone();
    await openHub(tester, 'tabs', roles: _wolf);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Scena 2'), findsOneWidget);
    expect(find.text('Tempo'), findsNothing);
    await openTab(tester, 'Piosenki');
    expect(find.text('Scena 2'), findsNothing);
    expect(find.textContaining('śpiewa: Chór, Błystek'), findsOneWidget);
    await openTab(tester, 'Ustawienia próby');
    expect(find.text('Tempo'), findsOneWidget);
    await openTab(tester, 'Narzędzia');
    expect(find.text('Eksportuj talię Anki'), findsOneWidget);
  });

  testWidgets('desktop: a side rail instead', (tester) async {
    tester.useDesktop();
    await openHub(tester, 'tabs-wide', roles: _wolf);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await openTab(tester, 'Ustawienia próby');
    expect(find.text('Tempo'), findsOneWidget);
  });

  testWidgets('one tap records a scene: auto-advance, meter, saved', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'rec-walk', roles: _wolf);
    await tester.tap(find.byTooltip('Nagraj czasy: Scena 1'));
    await _settle(tester);
    expect(find.text('Kwestia 1/2'), findsOneWidget);
    expect(find.text('Piaskowe Wilki nie jedzą Krasnali!'), findsOneWidget);
    rig.capture.level.value = 0.6;
    await tester.pump();
    final meter = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('level')),
    );
    expect(meter.value, 0.6);

    rig.capture.hear(take(2, 'piaskowe wilki nie jedzą krasnali'));
    await _settle(tester);
    expect(find.text('Kwestia 2/2'), findsOneWidget);
    expect(find.text('Naprawdę.'), findsOneWidget);
    expect(find.text('Zapisano kwestię 2: 2,0 s (+1 s pauzy)'), findsOneWidget);

    final wav = pcmToWav(Uint8List(16000 * 2), sampleRate: 16000);
    rig.capture.hear(
      CaptureResult(speechStart: 1, speechEnd: 2, transcript: 'x', audio: wav),
    );
    await _settle(tester);
    expect(find.text('Gotowe: zapisano 2 z 2'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds, {2: 3.0});
    expect(prefs.recordings.keys, [4]);
    await tester.tap(find.text('Zamknij'));
    await tester.pumpAndSettle();
    expect(find.text('Moje role'), findsOneWidget);
  });

  testWidgets('a skipped line is flagged; Stop ends the walk', (tester) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'rec-skip',
      roles: _wolf,
      tab: 'Narzędzia',
    );
    await tester.tapVisible(find.text('Czasy i nagrania'));
    await tester.tap(find.text('Nagraj czasy'));
    await _settle(tester);
    expect(find.text('Kwestia 1/3'), findsOneWidget);
    rig.capture.hear(take(1.2, 'naprawdę'));
    await _settle(tester);
    expect(find.byKey(const Key('skip-warning')), findsOneWidget);
    await tester.tap(find.text('Tak, zapisz tam'));
    await _settle(tester);
    expect(find.text('Kwestia 3/3'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await _settle(tester);
    expect(find.text('Gotowe: zapisano 1 z 3'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds, {4: 2.2});
    expect(rig.capture.listening, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pauza 2,2 s · ręcznie'), findsOneWidget);
  });
}
