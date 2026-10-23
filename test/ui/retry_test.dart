import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/pure_run.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _cue = 'Dzień dobry, Wilku!';
const _line2 = 'Piaskowe Wilki nie jedzą Krasnali!';
const _badge = Key('pure-scena-1');

Future<void> _speakDone(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
  await t.pump();
}

Future<void> _say(WidgetTester t, String grade) async {
  await t.tap(find.text('Gotowe'));
  await t.pump();
  await t.tap(find.text(grade));
  await t.pump();
}

String _header(WidgetTester t) =>
    t.widget<Text>(find.textContaining('Przebieg').first).data!;

void main() {
  testWidgets('Źle hides my line, replays the cue, asks until Dobrze', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'retry', roles: _wolf);
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    await _say(tester, 'Źle');
    // Hidden again; the partner's cue is played once more.
    expect(find.text(_line2), findsNothing);
    expect(find.text('Jak poszło?'), findsNothing);
    expect(find.byKey(const Key('retry')), findsOneWidget);
    expect(rig.speech.said, [_cue, _cue]);
    await _speakDone(tester);
    expect(find.text('Mów z pamięci…'), findsOneWidget);
    expect(_header(tester), contains('kwestia 2/4'));
    // Space still ends the line; a second Źle loops again.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text(_line2), findsOneWidget);
    await tester.tap(find.text('Źle'));
    await tester.pump();
    await _speakDone(tester);
    await _say(tester, 'Dobrze');
    expect(_header(tester), contains('kwestia 3/4'));
    expect(find.byKey(const Key('retry')), findsNothing);
    await _say(tester, 'Dobrze');
    await _speakDone(tester);
    expect(find.text('Koniec'), findsOneWidget);
    expect(find.text('Przebieg 1: 1/2'), findsOneWidget);
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.knowledge, {
      2: [false],
      4: [true],
    });
    expect(prefs.missed, {2});
    expect(prefs.pureRuns, isEmpty);
    expect(find.byKey(_badge), findsNothing);
  });

  testWidgets('leaving mid-retry keeps the ✗: resumed ✓ is not first', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'retry-resume', roles: _wolf);
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    await _say(tester, 'Źle');
    expect(find.byKey(const Key('retry')), findsOneWidget);
    await leaveRehearsal(tester);

    await tester.tap(find.byKey(const Key('learn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_header(tester), contains('kwestia 2/4'));
    expect(find.byKey(const Key('retry')), findsOneWidget);
    await _say(tester, 'Dobrze');
    await _say(tester, 'Dobrze');
    await _speakDone(tester);
    expect(find.text('Koniec'), findsOneWidget);
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.knowledge, {
      2: [false],
      4: [true],
    });
    expect(prefs.missed, {2});
    expect(prefs.pureRuns, isEmpty);
    expect(find.byKey(_badge), findsNothing);
  });

  testWidgets('a pure run of a scene shows its badge in Sceny', (tester) async {
    tester.usePhone();
    final rig = await openHub(tester, 'pure', roles: _wolf);
    expect(find.byKey(_badge), findsNothing);
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    await _say(tester, 'Dobrze');
    await _say(tester, 'Dobrze');
    await _speakDone(tester);
    expect(find.text('Koniec'), findsOneWidget);
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.pureRuns, {'scena-1'});
    expect(find.byKey(_badge), findsOneWidget);
    expect(find.byTooltip('Czysty przebieg'), findsOneWidget);
  });

  test('only a whole scene or song walk can be a pure run', () {
    final s = fixtureScript();
    const scene = ResumePoint(label: 'Scena 1', start: 0, end: 5);
    expect(pureRunSection(s, scene)?.id, 'scena-1');
    expect(pureRunSection(s, scene.at(3))?.id, 'scena-1');
    const song = ResumePoint(label: 'Piosenka', start: 7, end: 9);
    expect(pureRunSection(s, song)?.id, 'piosenka');
    const missed = ResumePoint(
      label: 'Tylko nieumiane',
      start: 0,
      end: 5,
      missedOnly: true,
    );
    expect(pureRunSection(s, missed), isNull);
    const part = ResumePoint(label: 'Kwestie 1–4', start: 1, end: 4);
    expect(pureRunSection(s, part), isNull);
  });
}
