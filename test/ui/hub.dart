import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/ui/app.dart';

import 'fakes.dart';

/// Pops the rehearsal and lets the fake TTS timer of the interrupted line
/// run out, so no timer outlives the test.
Future<void> leaveRehearsal(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// Seeds the fixture script (+ prefs/settings), opens the app and the
/// script's hub screen.
Future<TestRig> openHub(
  WidgetTester tester,
  String db, {
  Set<Role> roles = const {},
  AppSettings settings = const AppSettings(),
  bool renderable = false,
  Future<void> Function(TestRig rig)? seed,
}) async {
  final rig = TestRig(db: db, renderable: renderable);
  await tester.io(() => rig.library.saveScript(rig.script));
  await tester.io(
    () => rig.library.savePrefs(rig.script.id, RehearsalPrefs(roles: roles)),
  );
  await tester.io(() => rig.library.saveSettings(settings));
  if (seed != null) await tester.io(() => seed(rig));
  await tester.pumpWidget(SuflerApp(services: rig.services));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Krasnale testowe'));
  await tester.pumpAndSettle();
  return rig;
}
