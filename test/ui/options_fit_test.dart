import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fit.dart';
import 'hub.dart';

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

void main() {
  for (final MapEntry(key: tab, value: segments) in _segments.entries) {
    testWidgets('$tab: every segment fits a Pixel 6a', (tester) async {
      usePixel6a(tester);
      await openHub(tester, 'options-$tab', renderable: true, tab: tab);
      for (final MapEntry(key: chip, value: items) in segments.entries) {
        await tester.tap(find.text(chip));
        await tester.pumpAndSettle();
        expectNoVerticalScroll(tester, screen: '$tab / $chip');
        for (final item in items) {
          expectHittable(find.textContaining(item), reason: '$chip: $item');
        }
        expectHittable(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tab),
          ),
          reason: 'nav bar',
        );
      }
    });
  }
}
