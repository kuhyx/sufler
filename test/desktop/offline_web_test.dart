// The desktop app is the web build served from disk: it must start with no
// network, so neither CanvasKit nor a font may come from a Google CDN.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/ui/fonts.dart';

void main() {
  test('every web build skips the CanvasKit CDN', () {
    final files = [
      File('packaging/install_arch.sh'),
      File('scripts/e2e_desktop.sh'),
      ...Directory('.github/workflows').listSync().whereType<File>(),
    ];
    var builds = 0;
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        if (!line.contains('flutter build web')) continue;
        if (line.trimLeft().startsWith('#')) continue;
        if (line.contains('echo')) continue;
        builds++;
        expect(line, contains('--no-web-resources-cdn'), reason: f.path);
      }
    }
    expect(builds, greaterThanOrEqualTo(2));
  });

  test('the default and symbol fonts are bundled, not fetched', () {
    // The web engine downloads Roboto from fonts.gstatic.com unless the app
    // ships a family named exactly "Roboto".
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final family in [bundledFont, symbolFont]) {
      expect(pubspec, contains('- family: $family'));
    }
    final assets = RegExp(r'asset: (fonts/\S+)').allMatches(pubspec);
    expect(assets, isNotEmpty);
    for (final m in assets) {
      expect(File(m[1]!).existsSync(), isTrue, reason: m[1]);
    }
    // "♪" (unheaded song titles) is not in Roboto: without a bundled
    // fallback the engine fetches a Noto font for it.
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      final style = withBundledFonts(theme).textTheme.bodyMedium!;
      expect(style.fontFamily, bundledFont);
      expect(style.fontFamilyFallback, [symbolFont]);
    }
  });
}
