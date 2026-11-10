import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/ui/app.dart';
import 'package:sufler/ui/library_grid.dart';

import 'fakes.dart';
import 'fit.dart';
import 'hub.dart';

/// Seeds [count] scripts ("Sztuka 1".."Sztuka N") and starts on the library.
Future<TestRig> openLibrary(WidgetTester tester, int count) async {
  final rig = TestRig(db: 'library-fit');
  for (var i = 1; i <= count; i++) {
    await tester.io(
      () => rig.library.saveScript(namedScript('s$i', 'Sztuka $i')),
    );
  }
  await tester.pumpWidget(SuflerApp(services: rig.services));
  await tester.pumpAndSettle();
  expect(find.byType(LibraryGrid), findsOneWidget, reason: 'no library');
  return rig;
}

void main() {
  testWidgets(
    'library fits a Pixel 6a, tiles hittable, details on long-press',
    (tester) async {
      usePixel6a(tester);
      await openLibrary(tester, 15);
      expectNoVerticalScroll(tester, screen: 'library');
      expectHittable(find.text('Sztuka 1'), reason: 'first tile');
      expectHittable(find.bySemanticsLabel('Importuj'), reason: 'import');

      await tester.longPress(find.text('Sztuka 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('s1.pdf'), findsOneWidget, reason: 'source');
      expect(bySpoken('kwestii'), findsOneWidget, reason: 'line count');
      expectHittable(
        find.bySemanticsLabel('Usuń'),
        reason: 'delete in the sheet',
      );
    },
  );

  testWidgets('every script is reachable by paging', (tester) async {
    usePixel6a(tester);
    await openLibrary(tester, 15);
    await pageTo(tester, find.text('Sztuka 15'));
    expectHittable(find.text('Sztuka 15'), reason: 'last tile');
  });

  testWidgets('library fits a desktop window', (tester) async {
    tester.useDesktop();
    await openLibrary(tester, 15);
    expectNoVerticalScroll(tester, screen: 'library desktop');
  });
}
