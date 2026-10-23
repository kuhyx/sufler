// Real-data checks of group roles and re-parse alignment against the
// (copyrighted, never committed) script. Asserts indices and counts only.
// Run with: SUFLER_SCRIPT_PDF=/path/to/krasnale.pdf flutter test \
//   test/import/krasnale_groups_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/import_document.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/groups.dart';
import 'package:sufler/storage/align.dart';

import '../storage/reparse_test.dart' show withLines;

final _path = Platform.environment['SUFLER_SCRIPT_PDF'];
const _skip = 'set SUFLER_SCRIPT_PDF to run';

const _krasnale = [
  'blystek',
  'koszalek-opalek',
  'podziomek',
  'pietrzyk',
  'zagiewka',
];

void main() {
  late Script s;
  setUpAll(() async {
    final path = _path;
    if (path == null) return;
    final file = File(path);
    s = await importDocument(
      fileName: file.uri.pathSegments.last,
      bytes: file.readAsBytesSync(),
    );
  });

  test('group speakers of the play', () {
    final groups = {for (final g in groupOptions(s)) g.role: g};
    final krasnale = Role.group(_krasnale);
    expect(groups[const Role.character('wszyscy')]!.count, 3);
    final snow = groups[const Role.character('sniezynki')]!;
    expect(snow.count, 12);
    expect(snow.members, {'sniezynka-1', 'sniezynka-2'});
    expect(groups[krasnale]!.count, 44);
    expect(groups[Role.group(const [])]!.count, 4);
    expect(suggestedGroups(groupOptions(s), {'zagiewka'}), {
      const Role.character('wszyscy'),
      krasnale,
    });
    // Żagiewka already sings every krasnale line.
    expect(extraLines(s, krasnale, {const Role.character('zagiewka')}), 0);
  }, skip: _path == null ? _skip : false);

  test('an old parse with "Finał" glued to the line before aligns', () {
    final f = s.scenes.last.start;
    expect(s.lines[f].text, 'Finał');
    final before = s.lines[f - 1];
    // The parse before 4b38694: the heading was part of Żagiewka's speech.
    final old = withLines(s, [
      ...s.lines.sublist(0, f - 1),
      before.copyWith(text: '${before.text}\nFinał'),
      ...s.lines.sublist(f + 1),
    ]);
    final map = alignLines(old.lines, s.lines);
    for (var i = 0; i < f; i++) {
      expect(map[i], i, reason: 'old line $i');
    }
    for (var i = f; i < old.lines.length; i++) {
      expect(map[i], i + 1, reason: 'old line $i');
    }
    final lostSpoken = [
      for (final l in old.lines)
        if (l.isSpoken && !map.containsKey(l.index)) l.index,
    ];
    expect(lostSpoken, isEmpty);
  }, skip: _path == null ? _skip : false);
}
