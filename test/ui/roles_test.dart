import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';

import '../rehearsal/group_fixture.dart';
import 'fakes.dart';
import 'hub.dart';

final _trio = Role.group(['ala', 'bolek', 'cela']);

Future<Set<Role>> _saved(WidgetTester t, TestRig rig) async =>
    (await t.io(() => rig.library.loadPrefs('grp'))).roles;

CheckboxListTile _check(WidgetTester t, String title) =>
    t.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, title));

void main() {
  testWidgets('roles: groups pre-ticked for my character, untickable', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'roles', script: groupScript());
    // The hub does not cover the screen with roles: it is its own screen.
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(bySpoken('Moje role'));
    await tester.pumpAndSettle();
    expect(find.text('Ala (5)'), findsOneWidget);
    // Ensembles are listed as groups, not as people.
    expect(find.widgetWithText(FilterChip, 'Wszyscy (1)'), findsNothing);
    for (final g in ['Wszyscy (1)', 'Śnieżynki (1)', 'Ala, Bolek, Cela (4)']) {
      expect(find.widgetWithText(CheckboxListTile, g), findsOneWidget);
    }
    expect(find.byIcon(Icons.groups), findsWidgets);

    await tester.tap(find.text('Ala (5)'));
    await tester.pumpAndSettle();
    expect(await _saved(tester, rig), {
      const Role.character('ala'),
      const Role.character('wszyscy'),
      _trio,
    });
    expect(_check(tester, 'Ala, Bolek, Cela (4)').value, isTrue);
    final trio = find.widgetWithText(CheckboxListTile, 'Ala, Bolek, Cela (4)');
    for (final note in ['twoja grupa', 'te kwestie już masz']) {
      expect(find.descendant(of: trio, matching: bySpoken(note)), findsOne);
    }
    expect(_check(tester, 'Śnieżynki (1)').value, isFalse);

    await tester.tap(find.text('Wszyscy (1)'));
    await tester.pumpAndSettle();
    expect(await _saved(tester, rig), {const Role.character('ala'), _trio});
    // The chorus is offered, not suggested; picking it adds its line.
    await tester.tapVisible(bySpoken('Chór (kwestie bez przypisania)'));
    expect(await _saved(tester, rig), contains(Role.group(const [])));

    await tester.tapVisible(bySpoken('Gotowe'));
    expect(bySpoken('Moje role'), findsOneWidget); // back on the hub
  });

  testWidgets('song picker previews singers, size and lyrics', (tester) async {
    tester.usePhone();
    final rig = await openHub(tester, 'songs', script: groupScript());
    await tester.tap(bySpoken('Moje role'));
    await tester.pumpAndSettle();
    final title = find.text('Piosenka Hej (4)');
    await tester.scrollUntilVisible(
      title,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ala, Bolek, Cela'), findsOneWidget);
    expect(bySpoken('Chór'), findsWidgets);
    expect(bySpoken('4 wersy'), findsOneWidget);
    expect(find.text('Hej ho idziemy'), findsOneWidget);
    expect(find.text('Do domu wracamy'), findsOneWidget);
    expect(find.text('La la la'), findsNothing);
    await tester.tapVisible(bySpoken('Pokaż cały tekst'));
    expect(find.text('La la la'), findsOneWidget);
    await tester.tapVisible(bySpoken('Zwiń'));
    expect(find.text('La la la'), findsNothing);

    await tester.tapVisible(title);
    expect(await _saved(tester, rig), {const Role.song('hej')});
  });
}
