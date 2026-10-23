/// Where a Google Doc export is downloaded from on this platform.
library;

export 'package:sufler/import/gdoc_endpoint_io.dart'
    if (dart.library.js_interop) 'package:sufler/import/gdoc_endpoint_web.dart';
