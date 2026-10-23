// coverage:ignore-file
// Platform glue: only loads in a browser.
import 'package:http/http.dart' as http;
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/ui/platform/vad_capture.dart';

/// Desktop: the mic through `record`, end of speech by VAD, the text from
/// the voice service (`/api/tts/transcribe`) when it has a recognizer.
SpeechCapture openSpeechCapture() {
  final client = TranscribeClient(client: http.Client(), base: Uri.base);
  return VadCapture(transcribe: client.transcribe);
}
