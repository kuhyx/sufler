import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';

import '../rehearsal/fake_capture.dart';
import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _line2 = 'Piaskowe Wilki nie jedzą Krasnali!';

Future<void> _speakDone(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
  await t.pump();
}

String _header(WidgetTester t) =>
    t.widget<Text>(find.textContaining('Przebieg').first).data!;

void main() {
  testWidgets('learning: hidden, said, revealed, graded; missed practice', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'learn', roles: _wolf);
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(find.text('Mów z pamięci…'), findsOneWidget);
    expect(find.text(_line2), findsNothing);
    // The countdown runs out by itself: the text is revealed for grading.
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.text('Jak poszło?'), findsOneWidget);
    expect(find.text(_line2), findsOneWidget);
    await tester.tap(find.text('Źle'));
    await tester.pump();
    expect(find.text('Naprawdę.'), findsNothing);
    // Asked again after the cue; the ✓ retry does not count as known.
    await _speakDone(tester);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    expect(_header(tester), contains('kwestia 3/4'));
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.missed, {2});

    // "Only lines I missed": line 2 with its prompt, line 1.
    await tester.tapVisible(find.text('Tylko nieumiane (1)'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tylko nieumiane'), findsOneWidget);
    expect(_header(tester), contains('/2'));
    expect(find.text('Dzień dobry, Wilku!'), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('the app resumes the last section where it stopped', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'resume',
      roles: _wolf,
      seed: (rig) => rig.library.updatePrefs(
        'abc123',
        (p) => p.copyWith(
          resume: const ResumePoint(label: 'Scena 1', start: 0, end: 5).at(2),
        ),
      ),
    );
    final learn = find.byKey(const Key('learn'));
    expect(
      find.descendant(of: learn, matching: find.textContaining('kwestia 3')),
      findsOneWidget,
    );
    await tester.tap(learn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_header(tester), contains('kwestia 3/4'));
    expect(find.text('Twoja kwestia'), findsOneWidget);
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    await leaveRehearsal(tester);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.resume!.position, 3);
    expect(
      find.textContaining('Ucz się dalej: Scena 1 · kwestia 4'),
      findsOneWidget,
    );
  });

  testWidgets('listening suggests ✓ from the transcript; Enter confirms', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'listen',
      roles: _wolf,
      settings: const AppSettings(listen: true),
    );
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(rig.capture.listening, isTrue);
    expect(find.text('Mów z pamięci… słucham'), findsOneWidget);
    rig.capture.hear(take(2.5, 'piaskowe wilki nie jedzą krasnali'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Jak poszło?'), findsOneWidget);
    expect(find.byKey(const Key('heard')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Dobrze'),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Twoja kwestia'), findsOneWidget);
    // A wrong take pre-selects ✗.
    rig.capture.hear(take(1, 'coś zupełnie innego tu było'));
    await tester.pump();
    await tester.pump();
    expect(
      find.ancestor(of: find.text('Źle'), matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.knowledge, {
      2: [true],
      4: [false],
    });
    await leaveRehearsal(tester);
  });

  testWidgets('−/+ on my line change its pause and persist it', (tester) async {
    tester.usePhone();
    final rig = await openHub(tester, 'pause', roles: _wolf);
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(find.text('Pauza 7,4 s'), findsOneWidget);
    await tester.tap(find.byTooltip('Dłuższa pauza'));
    await tester.pump();
    expect(find.text('Pauza 7,9 s'), findsOneWidget);
    await tester.tap(find.byTooltip('Dłuższa pauza'));
    await tester.tap(find.byTooltip('Krótsza pauza'));
    await tester.pump();
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.lineSeconds[2], closeTo(7.94, 0.01));
    await leaveRehearsal(tester);

    // The next rehearsal uses it.
    await tester.tapVisible(find.text('Scena 1'));
    await _speakDone(tester);
    expect(find.text('Pauza 7,9 s'), findsOneWidget);
    await leaveRehearsal(tester);
  });
}
