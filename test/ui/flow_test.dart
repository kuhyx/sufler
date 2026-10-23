import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/app.dart';

import 'fakes.dart';

void main() {
  testWidgets('first run: import, roles screen once, then learn', (
    tester,
  ) async {
    final rig = TestRig(db: 'flow');
    rig.files.next = (name: 'sztuka.pdf', bytes: Uint8List(1));
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expect(find.text('Brak skryptów'), findsOneWidget);

    await tester.tap(find.text('Importuj plik'));
    await tester.pumpAndSettle();
    expect(rig.imported, ['sztuka.pdf']);
    // No roles yet: the roles screen opens by itself.
    expect(find.widgetWithText(AppBar, 'Moje role'), findsOneWidget);
    await tester.tap(find.text('Piaskowy Wilk (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gotowe'));
    await tester.pumpAndSettle();
    expect(find.text('Krasnale testowe'), findsOneWidget);

    await tester.tap(find.text('Scena 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Partner line: read aloud by TTS, only its speaker on screen (on
    // stage nobody holds the partners' text).
    expect(find.text('Błystek'), findsOneWidget);
    expect(find.text('Dzień dobry, Wilku!'), findsNothing);
    expect(rig.speech.said, ['Dzień dobry, Wilku!']);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    // My line: countdown running, my text NOT shown.
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.text('Piaskowe Wilki nie jedzą Krasnali!'), findsNothing);
    final before = tester.widget<Text>(find.byKey(const Key('countdown')));
    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<Text>(find.byKey(const Key('countdown')));
    expect(after.data, isNot(before.data));

    // Said it: the text is revealed for grading.
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text('Jak poszło?'), findsOneWidget);
    expect(find.text('Piaskowe Wilki nie jedzą Krasnali!'), findsOneWidget);
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    expect(find.text('Twoja kwestia'), findsOneWidget);

    // Space ends my line too; ✗ marks it as not known and asks it again
    // (after the line before it) until ✓.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.text('Źle'));
    await tester.pump();
    expect(find.text('Naprawdę.'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(find.text('Dobrze'));
    await tester.pump();
    expect(rig.speech.said.last, 'No dobrze.');
    expect(find.text('No dobrze.'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Koniec'), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget);
    final prefs = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(prefs.knowledge, {
      2: [true],
      4: [false],
    });
    expect(prefs.rolesAsked, isTrue);
  });

  testWidgets('import from a Google Docs link; delete from the library', (
    tester,
  ) async {
    final rig = TestRig(db: 'flow-link');
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('gdoc-url')),
      'https://docs.google.com/document/d/x/edit',
    );
    await tester.tap(find.text('Importuj link'));
    await tester.pumpAndSettle();
    expect(rig.imported, ['https://docs.google.com/document/d/x/edit']);
    await tester.pageBack(); // roles screen
    await tester.pumpAndSettle();
    await tester.pageBack(); // script
    await tester.pumpAndSettle();
    expect(find.text('Krasnale testowe'), findsOneWidget);
    await tester.tap(find.byTooltip('Usuń'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń').last);
    await tester.pumpAndSettle();
    expect(find.text('Brak skryptów'), findsOneWidget);
    expect(await tester.io(() => rig.library.scripts()), isEmpty);
  });

  testWidgets('a restart opens the last script; import is the + action', (
    tester,
  ) async {
    final rig = TestRig(db: 'flow-last');
    final other = rig.script;
    await tester.io(() => rig.library.saveScript(other));
    await tester.io(
      () => rig.library.saveScript(
        Script(
          id: 'zzz',
          title: 'Inna sztuka',
          source: 'b.txt',
          characters: other.characters,
          scenes: other.scenes,
          songs: other.songs,
          lines: other.lines,
        ),
      ),
    );
    await tester.io(
      () =>
          rig.library.savePrefs('zzz', const RehearsalPrefs(rolesAsked: true)),
    );
    await tester.io(
      () => rig.library.saveSettings(const AppSettings(lastScriptId: 'zzz')),
    );
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Inna sztuka'), findsOneWidget);
    expect(find.text('Importuj plik'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Krasnale testowe'), findsOneWidget);
    await tester.tap(find.byTooltip('Importuj'));
    await tester.pumpAndSettle();
    expect(find.text('Importuj plik'), findsOneWidget);

    // Opening the other script makes it the one to start with.
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Krasnale testowe'));
    await tester.pumpAndSettle();
    final s = await tester.io(() => rig.library.loadSettings());
    expect(s.lastScriptId, 'abc123');
  });

  testWidgets('starting without a role asks for one', (tester) async {
    final rig = TestRig(db: 'flow-norole');
    await tester.io(() => rig.library.saveScript(rig.script));
    await tester.io(
      () => rig.library.savePrefs(
        rig.script.id,
        const RehearsalPrefs(rolesAsked: true),
      ),
    );
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz swoje role'), findsOneWidget);
    await tester.tap(find.text('Scena 1'));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz co najmniej jedną rolę'), findsOneWidget);
  });
}
