/// Voice rendering: `renderAvailable()` and `renderPack(script)`.
///
/// Web (desktop) talks to the local voice service through the wrapper's
/// `/api/tts/*` proxy; io (Android) has no GPU renderer, so it says "no".
library;

export 'render_pack_io.dart'
    if (dart.library.js_interop) 'render_pack_web.dart';
export 'render_progress.dart';
