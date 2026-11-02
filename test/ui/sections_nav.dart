import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Long-presses the tile titled [title] on Sceny/Piosenki, paging to it if
/// needed; this opens its details sheet (range, progress, notes, "Nagraj
/// czasy").
Future<void> openSectionDetails(WidgetTester tester, String title) async {
  final tile = find.text(title);
  for (var i = 0; i < 10 && tile.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(PageView).first, const Offset(-400, 0));
    await tester.pumpAndSettle();
  }
  await tester.longPress(tile.first);
  await tester.pumpAndSettle();
}

/// Closes the details sheet.
Future<void> closeSectionDetails(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}
