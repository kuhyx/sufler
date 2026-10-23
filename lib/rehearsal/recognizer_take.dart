import 'package:sufler/rehearsal/capture.dart';

/// One listen of a recognizer that keeps no audio (Android
/// speech_to_text), built from its callbacks: the platform-independent
/// half of that [SpeechCapture]. The speech span comes from sound levels:
/// the first [calibrateSeconds] set the noise floor, speech is anything
/// [aboveFloorDb] above it.
class RecognizerTake {
  /// Noise-floor calibration at the start of the listen.
  static const double calibrateSeconds = 0.5;

  /// Speech threshold above the floor.
  static const double aboveFloorDb = 4;

  /// Whether this listen's own "listening" status has arrived. Before it,
  /// statuses and results are stragglers from the previous listen.
  bool get live => _live;
  bool _live = false;

  /// What was recognised so far.
  String text = '';

  double _floorSum = 0;
  int _floorN = 0;
  double? _start;
  double? _end;

  /// Marks the listen as started.
  void started() => _live = true;

  /// Sound level [db] heard [at] seconds into the listen.
  void level(double db, double at) {
    if (at < calibrateSeconds) {
      _floorSum += db;
      _floorN++;
    } else if (db > (_floorN == 0 ? 0 : _floorSum / _floorN) + aboveFloorDb) {
      _start ??= at;
      _end = at;
    }
  }

  /// Words recognised so far; true for the first words of the take, when
  /// the long wait for the actor to begin can shrink to the end pause.
  bool words(String recognized) {
    if (!_live) return false;
    final first = text.isEmpty && recognized.isNotEmpty;
    text = recognized;
    return first;
  }

  /// The take after [elapsed] seconds; null when neither speech nor words
  /// were heard.
  CaptureResult? result(double elapsed) => text.isEmpty && _start == null
      ? null
      : CaptureResult(
          speechStart: _start ?? 0,
          speechEnd: _end ?? elapsed,
          transcript: text,
        );
}

/// Whether recognizer error [errorMsg] means it cannot work here at all
/// (no network for it, no Polish model, no mic), so the recorder should
/// take over. Silence or no match only mean nothing was understood.
bool recognizerUnusable(String errorMsg) => _unusable.contains(errorMsg);

const _unusable = {
  'error_network',
  'error_network_timeout',
  'error_server',
  'error_server_disconnected',
  'error_language_not_supported',
  'error_language_unavailable',
  'error_audio_error',
  'error_permission',
  'error_too_many_requests',
};
