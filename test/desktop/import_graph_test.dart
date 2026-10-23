import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `package:sufler/...` file reachable from [entry], plus [entry].
Set<String> reachable(String entry) {
  final seen = <String>{};
  final todo = [entry];
  final import = RegExp(
    r'''^(?:import|export)\s+'([^']+)'(?:\s+if\s*\([^)]*\)\s*'([^']+)')?''',
    multiLine: true,
  );
  while (todo.isNotEmpty) {
    final path = todo.removeLast();
    if (!seen.add(path)) continue;
    final dir = File(path).parent.path;
    for (final m in import.allMatches(File(path).readAsStringSync())) {
      for (final uri in [m.group(1), m.group(2)].whereType<String>()) {
        if (uri.startsWith('package:sufler/')) {
          todo.add('lib/${uri.substring('package:sufler/'.length)}');
        } else if (!uri.contains(':')) {
          todo.add('$dir/$uri');
        } else {
          seen.add(uri);
        }
      }
    }
  }
  return seen;
}

void main() {
  // The wrapper is compiled with `dart build cli` for the plain Dart VM,
  // which has no dart:ui. `flutter test` does, so a Flutter import would pass
  // every other wrapper test and only fail at packaging time.
  test('desktop wrapper never reaches package:flutter or dart:ui', () {
    final graph = reachable('bin/sufler_desktop.dart');
    expect(graph, contains('lib/desktop/wrapper_server.dart'));
    expect(graph, contains('lib/anki/apkg_writer.dart'));
    expect(
      graph.where((u) => u.startsWith('package:flutter') || u == 'dart:ui'),
      isEmpty,
    );
    expect(graph.where((u) => u.startsWith('lib/model/')), [
      'lib/model/json.dart',
    ]);
  });
}
