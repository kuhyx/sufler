import 'package:flutter_test/flutter_test.dart';
import 'package:kuhy_credit/kuhy_credit.dart';
import 'package:sufler/ui/app.dart';
import 'package:sufler/ui/library_grid.dart';

import 'fakes.dart';
import 'fit.dart';

/// Seeds [count] scripts ("Sztuka 1".."Sztuka N") and starts on the library.
Future<TestRig> openLibrary(WidgetTester tester, int count) async {
  final rig = TestRig(db: 'library-credit');
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
  testWidgets('library shows KuhyCredit widget', (tester) async {
    usePixel6a(tester);
    await openLibrary(tester, 15);
    expect(find.byType(KuhyCredit), findsOneWidget, reason: 'credit widget');
  });
}
