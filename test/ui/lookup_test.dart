import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/migrate.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/reparse.dart';

import '../rehearsal/fixture.dart';
import '../storage/reparse_test.dart' show newerParse;
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _cue = 'Dzień dobry, Wilku!';
const _offline = 'PC offline — wyślę, gdy będzie dostępny';

/// Partner text shown; Scena 1 started, its partner line 1 on screen.
Future<TestRig> _rehearse(WidgetTester t, String db) async {
  final rig = await openHub(
    t,
    db,
    roles: _wolf,
    settings: const AppSettings(partnerText: true),
  );
  // Long enough to look a word up while the partner line still plays.
  rig.speech.length = const Duration(seconds: 5);
  final scene = find.text('Scena 1');
  await t.ensureVisible(scene);
  await t.pumpAndSettle();
  await t.tap(scene);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  return rig;
}

/// Long-presses [word] inside the on-screen text [text].
Future<void> _longPressWord(WidgetTester t, String text, String word) async {
  final para = t.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  final at = text.indexOf(word) + 1;
  final caret = para.getOffsetForCaret(TextPosition(offset: at), Rect.zero);
  await t.longPressAt(para.localToGlobal(caret + const Offset(1, 8)));
  await t.pumpAndSettle();
}

/// Closes a sheet or dialog by its barrier; the rehearsal resumes.
Future<void> _close(WidgetTester t) async {
  await t.tapAt(const Offset(200, 40));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// Lets fake storage and assistant calls finish (the walk keeps going).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Leaves the rehearsal; the long fake utterance runs out.
Future<void> _leave(WidgetTester t) async {
  await t.pageBack();
  await t.pump(const Duration(seconds: 6));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('long-press a word: dictionary links, and "Zapytaj Claude" '
      'saves the answer as a note on the line', (tester) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'lookup');
    await _longPressWord(tester, _cue, 'Wilku');
    expect(find.text('„Wilku”'), findsOneWidget);
    await tester.tap(find.text('Słownik'));
    await tester.pump();
    expect(rig.links, ['https://sjp.pwn.pl/szukaj/Wilku.html']);
    await tester.tap(find.text('Wikisłownik'));
    await tester.pump();
    expect(rig.links.last, 'https://pl.wiktionary.org/wiki/Wilku');

    await tester.tap(find.text('Zapytaj Claude'));
    await tester.pumpAndSettle();
    expect(rig.assistant.explained, ['Wilku']);
    expect(find.text(rig.assistant.answer), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.notes[1]!.single.about, 'Wilku');
    expect(prefs.notes[1]!.single.text, rig.assistant.answer);

    // Closed: the line carries a note mark; tapping it reads the note.
    await _close(tester);
    expect(find.byTooltip('Notatki (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('Notatki (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(rig.assistant.answer), findsOneWidget);
    await tester.tap(find.text('Zamknij'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _leave(tester);

    // The scene list counts it; the Anki export carries it.
    expect(find.byTooltip('Notatki: Scena 1 (1)'), findsOneWidget);
    await openTab(tester, 'Narzędzia');
    await tester.tapVisible(find.text('Eksportuj talię Anki'));
    expect(rig.exportedNotes.last[1]!.single.text, rig.assistant.answer);
  });

  testWidgets('the sentence around the word can be asked about instead', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'lookup-sentence');
    await _longPressWord(tester, _cue, 'dobry');
    await tester.tap(find.text('całe zdanie'));
    await tester.pump();
    await tester.tap(find.text('Zapytaj Claude'));
    await tester.pumpAndSettle();
    expect(rig.assistant.explained, [_cue]);
    await _close(tester);
    await _leave(tester);
  });

  testWidgets('PC offline: the question waits and is answered once it is '
      'back, after the sheet was closed', (tester) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'lookup-offline');
    rig.assistant.online = false;
    await _longPressWord(tester, _cue, 'Wilku');
    await tester.tap(find.text('Zapytaj Claude'));
    await tester.pumpAndSettle();
    expect(find.text(_offline), findsOneWidget);
    await _close(tester);
    expect(find.byTooltip('Notatki (1)'), findsNothing);

    rig.assistant.setOnline(on: true);
    await _settle(tester);
    expect(rig.assistant.explained, ['Wilku', 'Wilku']);
    expect(find.byTooltip('Notatki (1)'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('notes stay on their line through a re-parse', (tester) async {
    final rig = await openHub(
      tester,
      'notes-reparse',
      roles: _wolf,
      seed: (rig) => rig.library.updatePrefs(
        'abc123',
        (p) => p.withNote(5, const LineNote(about: 'dobrze', text: 'zgoda')),
      ),
    );
    expect(find.byTooltip('Notatki: Scena 1 (1)'), findsOneWidget);
    await tester.io(() => rig.library.replaceParse(rig.script, newerParse()));
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    // "No dobrze." moved from 5 to 6 (a heading appeared before it).
    expect(prefs.notes.keys, [6]);
    expect(movePrefs(prefs, {6: 6}, 10).prefs.notes[6]!.single.text, 'zgoda');
  });
}
