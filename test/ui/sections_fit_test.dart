import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';

import '../rehearsal/fixture.dart';
import 'fakes.dart';
import 'fit.dart';
import 'hub.dart';

void main() {
  for (final (tab, first) in [
    ('Sceny', 'Scena 2'),
    ('Piosenki', 'Piosenka 2'),
  ]) {
    testWidgets('$tab fits a Pixel 6a, details on long-press', (tester) async {
      usePixel6a(tester);
      await openHub(
        tester,
        'sections-fit-$tab',
        script: bigScript(),
        roles: {const Role.character(wolf)},
        tab: tab,
      );
      expectNoVerticalScroll(tester, screen: tab);
      expectHittable(find.text(first), reason: 'tile');
      expectHittable(find.text(tab), reason: 'nav bar');
      if (tab == 'Sceny') {
        expectHittable(find.text('Własny zakres…'), reason: 'custom range');
        expectHittable(find.text('Narastająco…'), reason: 'cumulative');
      }

      await tester.longPress(find.text(first));
      await tester.pumpAndSettle();
      expect(find.textContaining('umiem'), findsWidgets, reason: 'progress');
      expect(find.textContaining('kwestie'), findsWidgets, reason: 'range');
      expectHittable(find.textContaining('Nagraj czasy'), reason: 'record');
    });

    testWidgets('$tab: last tile reachable by paging', (tester) async {
      usePixel6a(tester);
      final last = tab == 'Sceny' ? 'Scena 40' : 'Piosenka 20';
      await openHub(
        tester,
        'sections-page-$tab',
        script: bigScript(),
        tab: tab,
      );
      await pageTo(tester, find.text(last));
      expectHittable(find.text(last), reason: 'last tile');
    });

    testWidgets('$tab fits a desktop window', (tester) async {
      tester.useDesktop();
      await openHub(
        tester,
        'sections-desk-$tab',
        script: bigScript(),
        tab: tab,
      );
      expectNoVerticalScroll(tester, screen: '$tab desktop');
    });
  }

  testWidgets('a long song title shows whole lines, never a clipped sliver', (
    tester,
  ) async {
    usePixel6a(tester);
    const long = 'Piosenka o bardzo długim tytule która nie mieści się';
    final base = bigScript(songs: 1);
    final song = base.songs.single;
    await openHub(
      tester,
      'sections-long-title',
      script: Script(
        id: base.id,
        title: base.title,
        source: base.source,
        characters: base.characters,
        scenes: base.scenes,
        songs: [Section(id: song.id, title: long, start: 0, end: song.end)],
        lines: base.lines,
      ),
      roles: {const Role.character(wolf)},
      tab: 'Piosenki',
    );
    final p = tester.renderObject<RenderParagraph>(find.text(long));
    final text = p.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: long.length),
    );
    final needed = text.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
    expect(needed, lessThanOrEqualTo(p.size.height + 0.5), reason: 'clipped');
    expect(
      text.map((b) => b.top.round()).toSet().length,
      greaterThanOrEqualTo(3),
    );
  });
}
