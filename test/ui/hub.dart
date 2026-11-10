import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/app.dart';

import 'fakes.dart';

/// Pops the rehearsal and lets the fake TTS timer of the interrupted line
/// run out, so no timer outlives the test.
Future<void> leaveRehearsal(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// Switches the script hub to tab [label] ("Sceny", "Piosenki",
/// "Ustawienia próby", "Narzędzia").
///
/// The labels are spoken-only (never painted, so not tappable): find the
/// destination's index by its label and tap its icon instead.
Future<void> openTab(WidgetTester tester, String label) async {
  final rail = find.byType(NavigationRail);
  final nav = rail.evaluate().isNotEmpty ? rail : find.byType(NavigationBar);
  final labels = find
      .descendant(
        of: nav,
        matching: find.byType(Text, skipOffstage: false),
        skipOffstage: false,
      )
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .toList();
  final index = labels.indexOf(label);
  expect(index, isNonNegative, reason: 'no tab "$label" in $labels');
  await tester.tap(
    find.descendant(of: nav, matching: find.byType(Icon)).at(index),
  );
  await tester.pumpAndSettle();
}

/// Finds a control by the words it keeps only as a spoken label (Icon
/// semanticLabel, Text semanticsLabel, or a Semantics widget). Unlike
/// find.bySemanticsLabel this also matches labels merged into a button.
/// (Icon and Text build such a Semantics widget themselves, so one
/// predicate covers all three without double matches.)
Finder bySpoken(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
  description: 'spoken label "$label"',
);

/// Seeds the fixture script (+ prefs/settings) and starts the app, which
/// opens the only script straight away (the roles screen counts as already
/// shown); optionally switches to [tab].
Future<TestRig> openHub(
  WidgetTester tester,
  String db, {
  Set<Role> roles = const {},
  AppSettings settings = const AppSettings(),
  bool renderable = false,
  String? tab,
  Script? script,
  Future<void> Function(TestRig rig)? seed,
}) async {
  final rig = TestRig(db: db, renderable: renderable);
  if (script != null) rig.script = script;
  await tester.io(() => rig.library.saveScript(rig.script));
  await tester.io(() => rig.library.saveMeta(rig.script));
  await tester.io(
    () => rig.library.savePrefs(
      rig.script.id,
      RehearsalPrefs(roles: roles, rolesAsked: true),
    ),
  );
  await tester.io(() => rig.library.saveSettings(settings));
  if (seed != null) await tester.io(() => seed(rig));
  await tester.pumpWidget(SuflerApp(services: rig.services));
  await tester.pumpAndSettle();
  expect(bySpoken('Moje role'), findsOneWidget, reason: 'hub not opened');
  if (tab != null) await openTab(tester, tab);
  return rig;
}

/// The rehearsal header's spoken words ("Przebieg 1 · kwestia 2/4 · …"):
/// painted as glyph + number pairs, so the words live in its Semantics.
String rehearsalHeader(WidgetTester t) => t
    .widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('rehearsal-header')),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .label!;

/// Like [bySpoken], for a spoken label containing [part].
Finder bySpokenContaining(String part) => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.label?.contains(part) ?? false),
  description: 'spoken label containing "$part"',
);
