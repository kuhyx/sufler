// coverage:ignore-file
// Platform glue: only loads in a browser; IdbStore itself is tested.
import 'package:idb_shim/idb_browser.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/store.dart';

/// IndexedDB in the browser profile.
Future<Store> openStore() async => IdbStore(idbFactoryBrowser);
