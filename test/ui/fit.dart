import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/model/script.dart';

import '../rehearsal/fixture.dart';

/// Pixel 6a portrait with its real insets: 1080x2400 physical at 2.625 dpr,
/// status bar 132 px and gesture nav 63 px (`adb shell dumpsys window`).
void usePixel6a(WidgetTester tester) {
  const insets = FakeViewPadding(top: 132, bottom: 63);
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = insets
    ..viewPadding = insets;
  addTearDown(tester.view.reset);
}

/// Fails when any vertical Scrollable on screen can scroll: the screen must
/// fit, with overflow paged sideways instead.
void expectNoVerticalScroll(WidgetTester tester, {String screen = ''}) {
  final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
  for (final s in states) {
    if (s.axisDirection != AxisDirection.down &&
        s.axisDirection != AxisDirection.up) {
      continue;
    }
    final p = s.position;
    if (!p.hasContentDimensions) continue;
    expect(
      p.maxScrollExtent,
      0,
      reason:
          '$screen: a vertical Scrollable '
          '(${s.widget.runtimeType}) scrolls by ${p.maxScrollExtent}',
    );
  }
}

/// Fails unless [finder] is on screen and receives taps.
void expectHittable(Finder finder, {String reason = ''}) {
  expect(finder.hitTestable(), findsWidgets, reason: reason);
}

/// Swipes the first horizontal PageView left until [finder] is built, at
/// most [pages] times.
Future<void> pageTo(
  WidgetTester tester,
  Finder finder, {
  int pages = 10,
}) async {
  for (var i = 0; i < pages && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(PageView).first, const Offset(-400, 0));
    await tester.pumpAndSettle();
  }
}

/// [base] with [scenes] scenes and [songs] songs, all over its last line, so
/// tiles overflow a phone screen. Titles are "Scena N" / "Piosenka N".
Script bigScript({int scenes = 40, int songs = 20, Script? base}) {
  final s = base ?? fixtureScript();
  final last = s.lines.length - 1;
  Section at(String id, String title) =>
      Section(id: id, title: title, start: 0, end: last);
  return Script(
    id: s.id,
    title: s.title,
    source: s.source,
    characters: s.characters,
    scenes: [for (var i = 1; i <= scenes; i++) at('scena-$i', 'Scena $i')],
    songs: [for (var i = 1; i <= songs; i++) at('song-$i', 'Piosenka $i')],
    lines: s.lines,
  );
}

/// The fixture script under another [id] and [title], for a library with
/// many scripts.
Script namedScript(String id, String title) {
  final s = fixtureScript();
  return Script(
    id: id,
    title: title,
    source: '$id.pdf',
    characters: s.characters,
    scenes: s.scenes,
    songs: s.songs,
    lines: s.lines,
  );
}
