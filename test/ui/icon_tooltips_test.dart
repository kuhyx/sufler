import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sufler/ui/app.dart';
import 'package:sufler/ui/pause_control.dart';

import 'fakes.dart';
import 'hub.dart';

/// Hovers a mouse over [target] past the tooltip delay.
Future<void> hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // The real app theme silences framework tooltips ("Back"); the app's own
  // icon words must still show on hover and long-press.
  testWidgets('hub role icon: word on hover', (tester) async {
    await openHub(tester, 'tip-hover');
    expect(find.text('Role'), findsNothing);
    await hover(tester, bySpoken('Moje role'));
    expect(find.text('Role'), findsOneWidget);
    expect(bySpoken('Moje role'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('hub role icon: word on long-press', (tester) async {
    tester.usePhone();
    await openHub(tester, 'tip-press');
    await tester.longPress(bySpoken('Moje role'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Role'), findsOneWidget);
    // A long-press shows the word; it does not open the roles screen.
    expect(bySpoken('Moje role'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('pause buttons: word on long-press under the app theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: PauseControl(length: 2, onAdjust: (_) {})),
      ),
    );
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pauza'), findsOneWidget);
    expect(find.bySemanticsLabel('Dłuższa pauza'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
