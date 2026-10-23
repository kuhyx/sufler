// The desktop app is the web build served from disk: it must start with no
// network, so neither CanvasKit nor a font may come from a Google CDN.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/ui/fonts.dart';

import 'font_cmap.dart';

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

  test('every non-ASCII character in UI text has a bundled glyph', () {
    // One the bundled fonts lack ("✓" in a switch title) makes the web
    // engine fetch a Noto font from fonts.gstatic.com.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final covered = <int>{
      for (final m in RegExp(r'asset: (fonts/\S+\.ttf)').allMatches(pubspec))
        ...bmpCoverage(m[1]!),
    };
    final missing = <String>[];
    final sources = Directory('lib/ui').listSync(recursive: true);
    for (final f in sources.whereType<File>()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final r in lines[i].runes.where((r) => r > 0x7F)) {
          if (!covered.contains(r)) {
            missing.add('${f.path}:${i + 1} U+${r.toRadixString(16)}');
          }
        }
      }
    }
    expect(covered, containsAll('Żółć♪'.runes));
    expect(missing, isEmpty);
  });
}
