// Platform selector: files on io (Android), IndexedDB on web.
export 'package:sufler/storage/open_store_io.dart'
    if (dart.library.js_interop) 'package:sufler/storage/open_store_web.dart';
