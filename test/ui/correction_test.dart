import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/app.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';

Future<TestRig> _openCorrection(WidgetTester tester, String db) async {
  final rig = TestRig(db: db);
  await tester.io(() => rig.library.saveScript(rig.script));
  await tester.io(
    () => rig.library.savePrefs(
      rig.script.id,
      RehearsalPrefs(roles: {const Role.character(elf)}),
    ),
  );
  await tester.pumpWidget(SuflerApp(services: rig.services));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Krasnale testowe'));
  await tester.pumpAndSettle();
  await tester.tapVisible(find.text('Popraw tekst'));
  return rig;
}

void main() {
  testWidgets('merge character A into B persists', (tester) async {
    final rig = await _openCorrection(tester, 'merge');
    await tester.tap(find.byTooltip('Scal postacie'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Błystek').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge-into')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piaskowy Wilk').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scal'));
    await tester.pumpAndSettle();

    final saved = (await tester.io(
      () => rig.library.loadScript(rig.script.id),
    ))!;
    expect(saved.characters.map((c) => c.id), [wolf]);
    expect(saved.characters.single.aliases, ['Błystek']);
    expect(saved.lines[1].speakers, [wolf]);
    final prefs = await tester.io(() => rig.library.loadPrefs(rig.script.id));
    expect(prefs.roles, {const Role.character(wolf)});

    // The hub shows the merged cast after returning.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Piaskowy Wilk (6)'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Piaskowy Wilk (6)'), findsOneWidget);
    expect(find.textContaining('Błystek ('), findsNothing);
  });

  testWidgets('edit a line kind and speakers', (tester) async {
    final rig = await _openCorrection(tester, 'edit');
    await tester.tap(find.text('Wilk siada.'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dialog').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Piaskowy Wilk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();

    final saved = (await tester.io(
      () => rig.library.loadScript(rig.script.id),
    ))!;
    expect(saved.lines[3].kind, LineKind.dialogue);
    expect(saved.lines[3].speakers, [wolf]);
  });
}
