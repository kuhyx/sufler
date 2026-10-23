import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/audio/pack_check.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/reparse.dart';
import 'package:sufler/ui/app.dart';
import 'package:sufler/ui/parse_refresh.dart';

import '../rehearsal/fixture.dart';
import '../storage/pack_zip_test.dart' show fixturePackZip;
import '../storage/reparse_test.dart' show newerParse;
import 'fakes.dart';
import 'hub.dart';

Uint8List _wav() => pcmToWav(Uint8List(3200), sampleRate: 16000);

Future<TestRig> _seedOld(WidgetTester tester, String db) async {
  final rig = TestRig(db: db);
  final lib = rig.library;
  await tester.io(() => lib.saveScript(fixtureScript()));
  await tester.io(() => lib.saveRecording('abc123', 7, _wav()));
  await tester.io(() => lib.saveRecording('abc123', 8, _wav()));
  await tester.io(
    () => lib.updatePrefs(
      'abc123',
      (p) => p.copyWith(
        roles: {const Role.character(wolf)},
        lineSeconds: {4: 9},
        rolesAsked: true,
      ),
    ),
  );
  return rig;
}

void main() {
  testWidgets('re-importing the same file re-parses and moves my data', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await _seedOld(tester, 'reimport');
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    // Stored before versions: only a re-import can refresh it.
    expect(find.text(reimportHint), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    rig
      ..script = newerParse()
      ..files.next = (name: 'krasnale.pdf', bytes: Uint8List.fromList([7]));
    await tester.tap(find.byTooltip('Importuj'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importuj plik'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Zaktualizowano parsowanie: 3 kwestie przeniesione, 0 utraconych',
      ),
      findsOneWidget,
    );
    final p = await tester.io(() => rig.library.loadPrefs('abc123'));
    expect(p.recordings.keys.toSet(), {8, 9});
    expect(p.lineSeconds, {5: 9.0});
    final s = await tester.io(() => rig.library.loadScript('abc123'));
    expect(s!.lines[3].text, 'Finał');
    expect(await tester.io(() => rig.library.loadSource('abc123')), [7]);
  });

  testWidgets('a newer parser re-reads the kept document on open', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await _seedOld(tester, 'upgrade');
    await tester.io(
      () => rig.library.saveSource('abc123', Uint8List.fromList([1])),
    );
    await tester.io(
      () => rig.library.store.writeJson('meta/abc123', {
        'parserVersion': 0,
        'parseFingerprint': fixtureScript().fingerprint,
      }),
    );
    rig.script = newerParse();
    await tester.pumpWidget(SuflerApp(services: rig.services));
    await tester.pumpAndSettle();
    expect(rig.imported, ['test.txt']);
    expect(find.textContaining('3 kwestie przeniesione'), findsOneWidget);
    final meta = await tester.io(() => rig.library.loadMeta('abc123'));
    expect(meta.fingerprint, newerParse().fingerprint);
  });

  testWidgets('a pack from another parse is ignored, never played', (
    tester,
  ) async {
    tester.usePhone();
    final rig = await openHub(
      tester,
      'stale-pack',
      roles: {const Role.character(wolf)},
      seed: (rig) =>
          rig.library.savePack('abc123', fixturePackZip(fingerprint: 'zzz')),
    );
    expect(find.text(stalePackMessage), findsOneWidget);
    await openTab(tester, 'Narzędzia');
    expect(find.textContaining('Brak paczki'), findsOneWidget);

    rig.files.next = (
      name: 'p.zip',
      bytes: fixturePackZip(fingerprint: 'other'),
    );
    await tester.tapVisible(find.text('Importuj paczkę audio (.zip)'));
    expect(find.text('Zła paczka audio: $stalePackMessage'), findsOneWidget);

    await openTab(tester, 'Sceny');
    await tester.tapVisible(find.text('Scena 1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.clips.played, isEmpty);
    expect(rig.speech.said, ['Dzień dobry, Wilku!']);
    await leaveRehearsal(tester);
  });
}
