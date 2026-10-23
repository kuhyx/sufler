/// The platform's assistant: `openAssistant(store)` and `openPcSession()`.
///
/// Web (desktop) talks to the voice service through the wrapper's
/// `/api/tts/*` proxy; io (Android) cannot reach the PC's loopback, so it
/// goes through the Firebase RTDB relay.
library;

export 'open_assistant_io.dart'
    if (dart.library.js_interop) 'open_assistant_web.dart';
