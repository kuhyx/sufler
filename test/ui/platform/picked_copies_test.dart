import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sufler/import/import_document.dart' show sha256Hex;
import 'package:sufler/ui/platform/picked_copies_io.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('file_picker'));
  tearDown(() => root.deleteSync(recursive: true));

  // file_picker's layout: <cache>/file_picker/<ms>/<display name>.
  void put(String ms, String name, List<int> bytes) =>
      File('${root.path}/$ms/$name')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  test('takes the same-named copy whose content hash is the id', () async {
    put('100', 'sztuka.pdf', [1]); // another version of the play
    put('200', 'sztuka.pdf', [2]);
    put('300', 'inna.pdf', [3]);
    final got = await findCopyIn(
      root,
      fileName: 'sztuka.pdf',
      id: sha256Hex([2]),
    );
    expect(got, [2]);
  });

  test('null when no copy matches, or the cache is gone', () async {
    put('100', 'sztuka.pdf', [1]);
    put('200', 'inna.pdf', [2]);
    expect(
      await findCopyIn(root, fileName: 'sztuka.pdf', id: sha256Hex([2])),
      isNull,
    );
    final gone = Directory('${root.path}/nothing');
    expect(await findCopyIn(gone, fileName: 'a.pdf', id: 'x'), isNull);
  });
}
