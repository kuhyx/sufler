import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fit.dart';
import 'hub.dart';
import 'options_nav.dart';

/// Each tab's segment chips and what each segment must still hold: nothing
/// from the old lists is dropped, it moves under one chip.
const _segments = {
  'Ustawienia próby': {
    'Tempo i tekst': ['Tempo', 'Pokaż tekst partnerów', 'Nauka', 'Czytanie'],
    'Tryby nauki': [
      'Oceniaj się ✓/✗',
      'Słuchaj mnie (mikrofon)',
      'Piosenki i monologi w całości',
      'Powtarzaj do skutku',
      'Czyste przebiegi',
    ],
  },
  'Narzędzia': {
    'Skrypt': ['Popraw tekst', 'Czasy i nagrania', 'Eksportuj talię Anki'],
    'Głosy': ['Generuj głosy', 'Importuj paczkę audio (.zip)'],
  },
};

/// Every option tile starts an [AppSpacing.md] gap below the chip row, has a
/// visible outline (its surface is nearly the page colour, so without one the
/// top edge vanishes), keeps its info icon an [AppSpacing.md] inside the top
/// edge, and titles line up across a row whether or not a tile has an icon.
void expectTilesClearChips(WidgetTester tester, {required String reason}) {
  var chipsBottom = 0.0;
  final chips = find.byType(ChoiceChip);
  for (var i = 0; i < chips.evaluate().length; i++) {
    chipsBottom = max(chipsBottom, tester.getRect(chips.at(i)).bottom);
  }
  expect(chipsBottom, greaterThan(0), reason: reason);
  final tiles = find.byType(Card);
  final titleTops = <double, double>{};
  for (var i = 0; i < tiles.evaluate().length; i++) {
    final tile = tester.getRect(tiles.at(i));
    final why = '$reason: tile $i';
    expect(
      tile.top,
      greaterThanOrEqualTo(chipsBottom + AppSpacing.md),
      reason: '$why top ${tile.top} vs chips $chipsBottom',
    );
    final shape = tester.widget<Card>(tiles.at(i)).shape;
    expect(
      shape is RoundedRectangleBorder && shape.side.style == BorderStyle.solid,
      isTrue,
      reason: '$why has no outline',
    );
    final icon = find.descendant(
      of: tiles.at(i),
      matching: find.byIcon(Icons.info_outline),
    );
    if (icon.evaluate().isNotEmpty) {
      expect(
        tester.getRect(icon).top - tile.top,
        greaterThanOrEqualTo(AppSpacing.md),
        reason: '$why info icon too close to the top edge',
      );
    }
    // Titles are icons now (textgate): the title is the topmost Text or
    // Icon below the tile's fixed 24 px icon row (leading/info icons).
    final title = find
        .descendant(
          of: tiles.at(i),
          matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
        )
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget).first))
        .where((r) => r.top >= tile.top + AppSpacing.md + 24 - 0.5)
        .reduce((a, b) => a.top <= b.top ? a : b);
    expect(
      titleTops.putIfAbsent(tile.top, () => title.top),
      title.top,
      reason: '$why title not aligned with its row neighbour',
    );
  }
}

/// A tile title [item], painted or (textgate) kept only as a spoken label.
Finder _named(String item) => find.byWidgetPredicate(
  (w) =>
      (w is Text && (w.data ?? '').contains(item)) ||
      (w is Semantics && (w.properties.label ?? '').contains(item)),
  description: 'title "$item"',
);

void main() {
  for (final MapEntry(key: tab, value: segments) in _segments.entries) {
    testWidgets('$tab: every segment fits a Pixel 6a', (tester) async {
      usePixel6a(tester);
      await openHub(tester, 'options-$tab', renderable: true, tab: tab);
      for (final MapEntry(key: chip, value: items) in segments.entries) {
        await openSegment(tester, chip);
        expectNoVerticalScroll(tester, screen: '$tab / $chip');
        expectTilesClearChips(tester, reason: '$tab / $chip');
        for (final item in items) {
          expectHittable(_named(item), reason: '$chip: $item');
        }
        expectHittable(
          // Nav labels are spoken-only (never painted): check the icons.
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.byType(Icon),
          ),
          reason: 'nav bar',
        );
      }
    });
  }
}
