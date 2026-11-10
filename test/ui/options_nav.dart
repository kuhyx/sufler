import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hub.dart';

/// Picks the chip [label] on "Ustawienia próby" / "Narzędzia" ("Tempo i
/// tekst", "Tryby nauki", "Skrypt", "Głosy"), so its group is on screen.
Future<void> openSegment(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(ChoiceChip), matching: bySpoken(label)),
  );
  await tester.pumpAndSettle();
}
