import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/app.dart';

import '../rehearsal/fixture.dart';
import '../storage/reparse_test.dart' show newerParse;
import 'fakes.dart';
import 'hub.dart';
import 'reparse_flow_test.dart' show seedOldParse;

const _summary =
    'Zaktualizowano parsowanie: 3 kwestie przeniesione, 0 utraconych';
const _tile = 'Odśwież parsowanie: wskaż plik';

Future<void> _open(WidgetTester tester, TestRig rig) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(SuflerApp(services: rig.services));
  await tester.pumpAndSettle();
}

Future<void> _expectMoved(WidgetTester tester, TestRig rig, int byte) async {
  final p = await tester.io(() => rig.library.loadPrefs('abc123'));
  expect(p.recordings.keys.toSet(), {8, 9});
  expect(p.lineSeconds, {5: 9.0});
  final s = await tester.io(() => rig.library.loadScript('abc123'));
  expect(s!.lines[3].text, 'Finał');
  expect(await tester.io(() => rig.library.loadSource('abc123')), [byte]);
}

void main() {
  testWidgets('an old script re-parses from the picker cache, once', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await seedOldParse(tester, 'cached');
    rig
      ..script = newerParse()
      ..pickedCopy = Uint8List.fromList([5]);
    await _open(tester, rig);
    expect(rig.copyLookups, ['test.txt']);
    expect(rig.imported, ['test.txt']);
    expect(find.text(_summary), findsOneWidget);
    await _expectMoved(tester, rig, 5);
    await openTab(tester, 'Narzędzia');
    expect(find.text(_tile), findsNothing);

    // Next open: the parse is current, the document kept: nothing to do.
    await _open(tester, rig);
    expect(rig.copyLookups, hasLength(1));
    expect(rig.imported, hasLength(1));
    expect(find.textContaining('Zaktualizowano parsowanie'), findsNothing);
  });

  testWidgets('no cached copy: silent, Narzędzia asks for the file', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await seedOldParse(tester, 'uncached');
    await _open(tester, rig);
    expect(rig.copyLookups, ['test.txt']);
    expect(rig.imported, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await openTab(tester, 'Narzędzia');

    // Another document: refused, nothing changes.
    rig
      ..script = Script.fromJson({...fixtureScript().toJson(), 'id': 'zzz'})
      ..files.next = (name: 'inna.pdf', bytes: Uint8List.fromList([6]));
    await tester.tapVisible(find.text(_tile));
    expect(find.textContaining('To inny plik niż ten skrypt'), findsOneWidget);
    expect(await tester.io(() => rig.library.loadSource('abc123')), isNull);

    rig
      ..script = newerParse()
      ..files.next = (name: 'test.txt', bytes: Uint8List.fromList([7]));
    await tester.tapVisible(find.text(_tile));
    expect(find.text(_summary), findsOneWidget);
    await _expectMoved(tester, rig, 7);
    expect(find.text(_tile), findsNothing);
  });
}
