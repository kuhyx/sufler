import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'hub.dart';

void main() {
  testWidgets('custom range: tap first and last line', (tester) async {
    tester.usePhone();
    await openHub(tester, 'custom', roles: {const Role.character(wolf)});
    await tester.tapVisible(find.text('Własny zakres…'));
    expect(find.text('Stuknij pierwszą kwestię.'), findsOneWidget);
    await tester.tap(find.text('No dobrze.'));
    await tester.pump();
    expect(find.text('Od 5. Stuknij ostatnią kwestię.'), findsOneWidget);
    await tester.tap(find.text('Naprawdę.'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Kwestie 4–5'), findsOneWidget);
    expect(find.text('Twoja kwestia'), findsOneWidget);
    await leaveRehearsal(tester);
  });

  testWidgets('cumulative from a scene start up to a line', (tester) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'cumulative',
      roles: {const Role.character(wolf)},
    );
    await tester.tapVisible(find.text('Narastająco…'));
    await tester.tap(find.byKey(const Key('cumulative-from')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Od: Scena 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koniec!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Kwestie 6–10'), findsOneWidget);
    expect(rig.speech.said.first, 'La la la');
    await leaveRehearsal(tester);
  });
}
