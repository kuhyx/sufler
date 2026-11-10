import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/labels.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';
import 'options_nav.dart';

void main() {
  testWidgets('roles and rehearsal settings persist across reopen', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(tester, 'settings');
    await tester.tap(bySpoken('Moje role'));
    await tester.pumpAndSettle();
    await tester.tapVisible(find.text('Piaskowy Wilk (3)'));
    await tester.tapVisible(find.text('Piosenka (3)'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openTab(tester, 'Ustawienia próby');
    await openSegment(tester, groupModes);
    await tester.tapVisible(bySpoken('Powtarzaj do skutku'));
    await tester.tapVisible(bySpoken('Więcej przebiegów'));
    await tester.tapVisible(bySpoken('Słuchaj mnie (mikrofon)'));
    await openSegment(tester, groupTempoText);
    await tester.tapVisible(bySpoken('Czytanie'));
    await tester.tapVisible(bySpoken('Pokaż tekst partnerów'));

    // Reopen from a brand-new library over the same IndexedDB.
    final fresh = ScriptLibrary(IdbStore(idbFactoryMemory, dbName: 'settings'));
    final prefs = await tester.io(() => fresh.loadPrefs(rig.script.id));
    expect(prefs.roles, {
      const Role.character(wolf),
      const Role.song('piosenka'),
    });
    final settings = await tester.io(() => fresh.loadSettings());
    expect(settings.loop, isTrue);
    expect(settings.cleanTarget, 4);
    expect(settings.visibility, TextVisibility.show);
    expect(settings.listen, isTrue);
    expect(settings.partnerText, isTrue);
    expect(settings.lastScriptId, rig.script.id);

    await tester.tap(bySpoken('Moje role'));
    await tester.pumpAndSettle();
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Piaskowy Wilk (3)'),
    );
    expect(chip.selected, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openSegment(tester, groupModes);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('a long press on a tile opens its explanation', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tile-info', tab: 'Ustawienia próby');
    await openSegment(tester, groupModes);
    await tester.longPress(bySpoken('Słuchaj mnie (mikrofon)'));
    await tester.pumpAndSettle();
    expect(
      find.text('kończy kwestię, gdy przestaniesz mówić, i podpowiada ocenę'),
      findsOneWidget,
    );
  });

  testWidgets('speed slider persists per script', (tester) async {
    tester.useDesktop();
    final rig = await openHub(tester, 'speed', tab: 'Ustawienia próby');
    await tester.ensureVisible(find.byType(Slider));
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    final prefs = await tester.io(() => rig.library.loadPrefs(rig.script.id));
    expect(prefs.speed, greaterThan(1));
  });
}
