import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/ui/app.dart';

import 'fakes.dart';

void main() {
  testWidgets('import -> pick Wolf -> pick scene -> rehearse', (tester) async {
    final rig = TestRig(db: 'flow');
    rig.files.next = (name: 'sztuka.pdf', bytes: Uint8List(1));
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expect(find.text('Brak skryptów'), findsOneWidget);

    await tester.tap(find.text('Importuj plik'));
    await tester.pumpAndSettle();
    expect(rig.imported, ['sztuka.pdf']);
    expect(find.text('Krasnale testowe'), findsOneWidget);

    await tester.tap(find.text('Piaskowy Wilk (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scena 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Partner line: text shown, read aloud by TTS.
    expect(find.text('Dzień dobry, Wilku!'), findsOneWidget);
    expect(rig.speech.said, ['Dzień dobry, Wilku!']);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    // My line: countdown running.
    expect(find.text('Twoja kwestia'), findsOneWidget);
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.text('Piaskowe Wilki nie jedzą Krasnali!'), findsOneWidget);
    final before = tester.widget<Text>(find.byKey(const Key('countdown')));
    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<Text>(find.byKey(const Key('countdown')));
    expect(after.data, isNot(before.data));

    // "Done" ends the pause early; the next own line gets its own pause.
    await tester.tap(find.text('Gotowe'));
    await tester.pump();
    expect(find.text('Naprawdę.'), findsOneWidget);
    expect(find.text('Twoja kwestia'), findsOneWidget);

    // Space works too.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('No dobrze.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Koniec'), findsOneWidget);
    expect(find.textContaining('2/2'), findsOneWidget);
  });

  testWidgets('import from a Google Docs link', (tester) async {
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
    expect(find.text('Krasnale testowe'), findsOneWidget);

    // Back in the library the script is listed and can be deleted.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Krasnale testowe'), findsOneWidget);
    await tester.tap(find.byTooltip('Usuń'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń').last);
    await tester.pumpAndSettle();
    expect(find.text('Brak skryptów'), findsOneWidget);
    expect(await tester.io(() => rig.library.scripts()), isEmpty);
  });

  testWidgets('starting without a role asks for one', (tester) async {
    final rig = TestRig(db: 'flow-norole');
    await tester.io(() => rig.library.saveScript(rig.script));
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Krasnale testowe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scena 1'));
    await tester.pumpAndSettle();
    expect(find.text('Wybierz co najmniej jedną rolę'), findsOneWidget);
  });
}
