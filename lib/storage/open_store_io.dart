// coverage:ignore-file
// Platform glue: needs a real path_provider host; FileStore itself is tested.
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sufler/storage/file_store.dart';
import 'package:sufler/storage/store.dart';

/// JSON + byte files under the app documents directory.
Future<Store> openStore() async {
  final docs = await getApplicationDocumentsDirectory();
  return FileStore(Directory('${docs.path}/sufler'));
}
