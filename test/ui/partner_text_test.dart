import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _cue = 'Dzień dobry, Wilku!';
const _speaking = Key('partner-speaking');

String _header(WidgetTester t) =>
    t.widget<Text>(find.textContaining('Przebieg').first).data!;

/// Starts Scena 1 and stops on its first (partner) line, still playing.
Future<void> _start(WidgetTester t) async {
  final scene = find.text('Scena 1');
  await t.ensureVisible(scene);
  await t.pumpAndSettle();
  await t.tap(scene);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a partner line shows who speaks, not what (default)', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'partner-hidden', roles: _wolf);
    await _start(tester);
    expect(rig.speech.said, [_cue]);
    expect(find.text('Błystek'), findsOneWidget);
    expect(find.byKey(_speaking), findsOneWidget);
    expect(find.text(_cue), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    // My line: the partner's line above it stays hidden too.
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.text(_cue), findsNothing);
    expect(find.text('(Błystek)'), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('"Pokaż tekst partnerów" shows the partner text', (tester) async {
    tester.usePhone();
    await openHub(
      tester,
      'partner-shown',
      roles: _wolf,
      settings: const AppSettings(partnerText: true),
    );
    await _start(tester);
    expect(find.text('Błystek'), findsOneWidget);
    expect(find.text(_cue), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.text(_cue), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('when the device cannot say it, the text is shown anyway', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'partner-mute', roles: _wolf);
    rig.speech.fail = true;
    await _start(tester);
    expect(find.text(_cue), findsOneWidget);
    expect(find.byKey(_speaking), findsNothing);
    // Held for its reading time, then my line; still readable above it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.text(_cue), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('back/next (buttons and arrows) step over partner lines and '
      'replay them', (tester) async {
    tester.useDesktop();
    final rig = await openHub(tester, 'partner-nav', roles: _wolf);
    await _start(tester);
    expect(_header(tester), contains('kwestia 1/4'));
    await tester.tap(find.byTooltip('Dalej'));
    await tester.pump();
    expect(_header(tester), contains('kwestia 2/4'));
    await tester.tap(find.byTooltip('Wstecz'));
    await tester.pump();
    expect(_header(tester), contains('kwestia 1/4'));
    expect(rig.speech.said, [_cue, _cue]);
    expect(find.text('Błystek'), findsOneWidget);
    expect(find.text(_cue), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_header(tester), contains('kwestia 2/4'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // The last partner line: voiced, its text hidden.
    expect(_header(tester), contains('kwestia 4/4'));
    expect(rig.speech.said.last, 'No dobrze.');
    expect(find.text('No dobrze.'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_header(tester), contains('kwestia 1/4'));
    expect(rig.speech.said, [_cue, _cue, 'No dobrze.', _cue]);
    await leaveRehearsal(tester);
  });
}
