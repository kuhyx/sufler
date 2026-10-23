import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/storage/reparse.dart';

import '../rehearsal/fixture.dart';
import '../storage/pack_zip_test.dart' show fixturePackZip;
import 'fakes.dart';
import 'hub.dart';

final _wolf = {const Role.character(wolf)};
const _new = 'Witaj, Wilku z lasu!';
const _tts = 'głos: syntezator do czasu wygenerowania';

/// Opens the hub with a pack (clips 1 and 2) whose clips play for 1 s, and
/// starts Scena 1: its partner line 1 is playing.
Future<TestRig> _rehearse(WidgetTester t, String db) async {
  final rig = await openHub(
    t,
    db,
    roles: _wolf,
    seed: (rig) => rig.library.savePack(
      'abc123',
      fixturePackZip(fingerprint: fixtureScript().fingerprint),
    ),
  );
  rig.clips.length = const Duration(seconds: 1);
  final scene = find.text('Scena 1');
  await t.ensureVisible(scene);
  await t.pumpAndSettle();
  await t.tap(scene);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  expect(rig.clips.bytes, [
    [1, 1],
  ]);
  return rig;
}

/// ✎ on the current line: new text, saved.
Future<void> _edit(WidgetTester t) async {
  await t.tap(find.byTooltip('Popraw kwestię'));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('line-text')), _new);
  await t.tap(find.text('Zapisz'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

/// Steps back to line 1 and lets it start again.
Future<void> _replay(WidgetTester t) async {
  await t.tap(find.byTooltip('Wstecz'));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('✎ on a partner line: correction logged, "zmieniono", new '
      'voice rendered and played from the pack', (tester) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'edit-voice');
    await _edit(tester);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final log = await tester.io(() => rig.library.loadCorrections('abc123'));
    expect(log.single['text'], _new);
    expect(log.single['was'], 'Dzień dobry, Wilku!');
    expect(find.text('zmieniono'), findsOneWidget);
    expect(rig.assistant.rendered, [(index: 1, text: _new)]);
    final pack = (await tester.io(() => rig.library.loadPack('abc123')))!;
    expect(pack.clip(1), [7, 7]);
    expect(find.text(_tts), findsNothing);
    await _replay(tester);
    expect(rig.clips.bytes.last, [7, 7]);
    await leaveRehearsal(tester);
  });

  testWidgets('PC offline: the edited line is said by device TTS until the '
      'PC is back, then rendered', (tester) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'edit-offline');
    rig.assistant.online = false;
    await _edit(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_tts), findsOneWidget);
    await _replay(tester);
    expect(rig.speech.said.last, _new);
    expect(rig.clips.bytes, [
      [1, 1],
    ]);

    rig.assistant.setOnline(on: true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(rig.assistant.rendered.length, 2);
    expect(find.text(_tts), findsNothing);
    final pack = (await tester.io(() => rig.library.loadPack('abc123')))!;
    expect(pack.clip(1), [7, 7]);
    await _replay(tester);
    expect(rig.clips.bytes.last, [7, 7]);
    await leaveRehearsal(tester);
  });

  testWidgets('an own line can be corrected too; the walk shows the new '
      'text', (tester) async {
    tester.usePhone();
    final rig = await _rehearse(tester, 'edit-own');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Twoja kwestia'), findsOneWidget);
    await _edit(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final s = (await tester.io(() => rig.library.loadScript('abc123')))!;
    expect(s.lines[2].text, _new);
    expect(find.text('zmieniono'), findsOneWidget);
    await leaveRehearsal(tester);
  });
}
