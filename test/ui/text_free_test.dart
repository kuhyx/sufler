import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/app.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'fit.dart';
import 'hub.dart';
import 'no_words.dart';
import 'sections_nav.dart';

/// textgate: every screen kuhy can reach paints no chrome words, only the
/// script's own text (titles, names, lines).
void main() {
  final content = scriptContent(fixtureScript());

  testWidgets('library, empty and filled, and its details sheet', (
    tester,
  ) async {
    usePixel6a(tester);
    final rig = TestRig(db: 'tf-lib');
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expectNoWords('empty library');

    // Two scripts: with one the app opens it straight away.
    final both = [namedScript('s1', 'Sztuka 1'), namedScript('s2', 'Sztuka 2')];
    for (final s in both) {
      await tester.io(() => rig.library.saveScript(s));
    }
    final titles = [for (final s in both) ...scriptContent(s)];
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expectNoWords('library', titles);
    await tester.longPress(find.text('Sztuka 1'));
    await tester.pumpAndSettle();
    expectNoWords('library details', titles);
    await tester.tap(bySpoken('Usuń'));
    await tester.pumpAndSettle();
    expectNoWords('delete confirmation', titles);
  });

  for (final tab in ['Sceny', 'Piosenki', 'Ustawienia próby', 'Narzędzia']) {
    testWidgets('hub tab $tab', (tester) async {
      tester.usePhone();
      await openHub(
        tester,
        'tf-$tab',
        roles: {const Role.character(wolf)},
        tab: tab,
      );
      expectNoWords(tab, content);
      for (final chip in find.byType(ChoiceChip).evaluate().toList()) {
        await tester.tap(find.byWidget(chip.widget));
        await tester.pumpAndSettle();
        expectNoWords('$tab chip', content);
      }
    });
  }

  testWidgets('section details sheet', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tf-sec', roles: {const Role.character(wolf)});
    await openSectionDetails(tester, 'Scena 1');
    expectNoWords('section details', content);
    await closeSectionDetails(tester);
  });

  testWidgets('roles screen', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tf-roles');
    await tester.tap(bySpoken('Moje role'));
    await tester.pumpAndSettle();
    expectNoWords('roles', content);
  });

  testWidgets('timings screen', (tester) async {
    tester.usePhone();
    await openHub(
      tester,
      'tf-tim',
      roles: {const Role.character(wolf)},
      tab: 'Narzędzia',
    );
    await tester.tapVisible(bySpoken('Czasy i nagrania'));
    expectNoWords('timings', content);
  });

  testWidgets('rehearsal: partner line, then my cue', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tf-reh', roles: {const Role.character(wolf)});
    await tester.tapVisible(find.text('Scena 1'));
    await tester.pump();
    expectNoWords('partner line', content);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expectNoWords('my cue', content);
    await leaveRehearsal(tester);
  });

  testWidgets('loop rehearsal: grade, then the summary', (tester) async {
    tester.usePhone();
    await openHub(
      tester,
      'tf-loop',
      roles: {const Role.character(wolf)},
      settings: const AppSettings(loop: true, cleanTarget: 1),
    );
    await tester.tapVisible(find.text('Scena 1'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(bySpoken('Gotowe'));
      await tester.pump();
      expectNoWords('grade', content);
      await tester.tap(bySpoken('Dobrze'));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(bySpoken('Koniec'), findsOneWidget);
    expectNoWords('summary', content);
    await leaveRehearsal(tester);
  });

  testWidgets('custom range picker', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tf-pick', roles: {const Role.character(wolf)});
    await tester.tapVisible(bySpoken('Własny zakres…'));
    expectNoWords('picker', content);
    await tester.tap(find.text('No dobrze.'));
    await tester.pump();
    expectNoWords('picker after first', content);
  });

  testWidgets('correction screen', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tf-cor', tab: 'Narzędzia');
    await tester.tapVisible(bySpoken('Popraw tekst'));
    expectNoWords('correction', content);
  });
}
