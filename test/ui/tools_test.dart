import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';

import '../rehearsal/fixture.dart';
import '../storage/pack_zip_test.dart' show fixturePackZip;
import 'fakes.dart';
import 'hub.dart';

void main() {
  testWidgets('Anki export saves the deck for the picked roles', (
    tester,
  ) async {
    final rig = await openHub(
      tester,
      'anki',
      tab: 'Narzędzia',
      roles: {const Role.character(wolf)},
    );
    await tester.tapVisible(find.text('Eksportuj talię Anki'));
    expect(rig.exported, [
      {const Role.character(wolf)},
    ]);
    expect(rig.files.saved.keys, ['Krasnale testowe.apkg']);
  });

  testWidgets('Anki export without roles asks for one', (tester) async {
    final rig = await openHub(tester, 'anki-none', tab: 'Narzędzia');
    await tester.tapVisible(find.text('Eksportuj talię Anki'));
    expect(rig.exported, isEmpty);
    expect(find.text('Wybierz co najmniej jedną rolę'), findsOneWidget);
  });

  testWidgets('import audio pack stores it and partners use clips', (
    tester,
  ) async {
    final rig = await openHub(
      tester,
      'pack',
      tab: 'Narzędzia',
      roles: {const Role.character(wolf)},
    );
    expect(find.text('Generuj głosy'), findsNothing);
    rig.files.next = (name: 'p.zip', bytes: fixturePackZip());
    await tester.tapVisible(find.text('Importuj paczkę audio (.zip)'));
    expect(find.text('Paczka: test@1, 2 kwestii.'), findsOneWidget);
    expect(await tester.io(() => rig.library.loadPack('abc123')), isNotNull);

    await openTab(tester, 'Sceny');
    await tester.tapVisible(find.text('Scena 1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.clips.played, ['audio/ogg']); // line 1 has a clip
    expect(rig.speech.said, isEmpty);
  });

  testWidgets('a pack for another script is rejected', (tester) async {
    final rig = await openHub(tester, 'pack-bad', tab: 'Narzędzia');
    rig.script = fixtureScript();
    rig.files.next = (name: 'x.zip', bytes: Uint8List.fromList([1, 2]));
    await tester.tapVisible(find.text('Importuj paczkę audio (.zip)'));
    expect(find.textContaining('Zła paczka audio'), findsOneWidget);
    expect(await tester.io(() => rig.library.loadPack('abc123')), isNull);
  });

  testWidgets('generate voices streams progress and stores the pack', (
    tester,
  ) async {
    final rig = await openHub(
      tester,
      'render',
      tab: 'Narzędzia',
      renderable: true,
    );
    await tester.tapVisible(find.text('Generuj głosy'));
    expect(find.text('Paczka: test@1, 2 kwestii.'), findsOneWidget);
    final stored = await tester.io(() => rig.library.loadPack('abc123'));
    expect(stored!.clip(2), [2, 2, 2]);
  });

  testWidgets('cancelled pick does nothing', (tester) async {
    final rig = await openHub(tester, 'pick-cancel', tab: 'Narzędzia');
    await tester.tapVisible(find.text('Importuj paczkę audio (.zip)'));
    expect(find.textContaining('Brak paczki'), findsOneWidget);
    expect(rig.files.saved, isEmpty);
  });
}
