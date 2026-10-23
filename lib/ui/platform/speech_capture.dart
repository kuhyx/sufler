// Platform selector: on-device recognizer on Android, recorder + VAD +
// the voice service's transcriber on web (desktop).
export 'package:sufler/ui/platform/speech_capture_io.dart'
    if (dart.library.js_interop) 'package:sufler/ui/platform/speech_capture_web.dart';
