import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};

/// A silent 16 kHz mono take of [s] seconds (32000 bytes a second).
Uint8List _take(double s) =>
    pcmToWav(Uint8List((s * 32000).round()), sampleRate: 16000);

/// His recordings: 0.4 s a syllable on lines 1 (5), 4 (3) and 5 (3).
/// Any recording counts as his pace, whoever's line it is.
Future<void> Function(TestRig) _seed(Map<int, double> takes) => (rig) async {
  for (final e in takes.entries) {
    await rig.library.saveRecording('abc123', e.key, _take(e.value));
  }
};

const _three = {1: 2.0, 4: 1.2, 5: 1.2};

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('own lines without a time are "szacowane" from his pace', (
    tester,
  ) async {
    tester.usePhone();
    await openHub(
      tester,
      'estimate-list',
      roles: _wolf,
      tab: 'Narzędzia',
      seed: _seed(_three),
    );
    await tester.tapVisible(find.text('Czasy i nagrania'));
    // 2: 11 syllables x 0.4 + 1 s; 4: its recording + 1 s; 10: 2 x 0.4 + 1.
    expect(find.text('Pauza 5,4 s · szacowane'), findsOneWidget);
    expect(find.text('Pauza 2,2 s · z nagrania'), findsOneWidget);
    expect(find.text('Pauza 1,8 s · szacowane'), findsOneWidget);
    await tester.tap(find.text('Koniec!'));
    await tester.pumpAndSettle();
    expect(find.text('Teraz: 1,8 s · szacowane'), findsOneWidget);
  });

  testWidgets('two recordings are not enough: the old default stays', (
    tester,
  ) async {
    tester.usePhone();
    await openHub(
      tester,
      'estimate-few',
      roles: _wolf,
      tab: 'Narzędzia',
      seed: _seed(const {1: 2.0, 4: 1.2}),
    );
    await tester.tapVisible(find.text('Czasy i nagrania'));
    expect(find.textContaining('szacowane'), findsNothing);
    expect(find.textContaining('automatycznie'), findsNWidgets(2));
  });

  testWidgets('−/+ on an estimated pause makes it a manual one', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'estimate-adjust',
      roles: _wolf,
      seed: _seed(_three),
    );
    await tester.tapVisible(find.text('Scena 1'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Pauza 5,4 s'), findsOneWidget);
    expect(find.text('szacowane'), findsOneWidget);
    await tester.tap(find.byTooltip('Dłuższa pauza'));
    await tester.pump();
    expect(find.text('Pauza 5,9 s'), findsOneWidget);
    expect(find.text('szacowane'), findsNothing);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds[2], closeTo(5.9, 0.01));
    await leaveRehearsal(tester);

    await openTab(tester, 'Narzędzia');
    await tester.tapVisible(find.text('Czasy i nagrania'));
    expect(find.text('Pauza 5,9 s · ręcznie'), findsOneWidget);
    expect(find.text('Pauza 1,8 s · szacowane'), findsOneWidget);
  });
  testWidgets('a time tapped in "Nagraj czasy" counts toward his pace', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'estimate-tap',
      roles: _wolf,
      // Two recordings only: not enough for an estimate on their own.
      seed: _seed(const {1: 2.0, 5: 1.2}),
    );
    await tester.tap(find.byTooltip('Nagraj czasy: Scena 1'));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('manual-walk')));
    await _settle(tester);
    // Real time must pass the tap guard (DateTime.now is not faked).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.tap(find.text('Skończyłem'));
    await _settle(tester);
    expect(find.text('Kwestia 2/2'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await _settle(tester);
    await tester.tap(find.text('Zamknij'));
    await tester.pumpAndSettle();
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds.keys, [2]);
    expect(prefs.recordings.keys, unorderedEquals([1, 5]));

    await openTab(tester, 'Narzędzia');
    await tester.tapVisible(find.text('Czasy i nagrania'));
    // The tap (line 2) is a third sample; the median stays 0.4 s/syllable.
    expect(find.text('Pauza 2,2 s · szacowane'), findsOneWidget);
    expect(find.text('Pauza 1,8 s · szacowane'), findsOneWidget);
    expect(find.textContaining('automatycznie'), findsNothing);
  });
}
