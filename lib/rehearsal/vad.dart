import 'dart:math' as math;
import 'dart:typed_data';

/// Energy-based end-of-speech detector over little-endian PCM16 mono.
///
/// The first [calibrateSeconds] measure the room's noise floor; after it a
/// frame is speech when its RMS exceeds [ratio] times that floor (and at
/// least [minRms]). Speech counts once [minSpeechSeconds] of it has been
/// heard; it has ended after [endSilenceSeconds] of silence following
/// that. Shorter blips followed by that much silence are forgotten.
class SpeechEndpoint {
  /// Creates a detector for audio at [sampleRate] Hz.
  new({
    required this.sampleRate,
    this.frameSeconds = 0.02,
    this.calibrateSeconds = 0.5,
    this.minSpeechSeconds = 0.3,
    this.endSilenceSeconds = 1.0,
    this.ratio = 3,
    this.minRms = 0.01,
  });

  /// Samples per second.
  final int sampleRate;

  /// Analysis frame length.
  final double frameSeconds;

  /// Noise-floor calibration at the start.
  final double calibrateSeconds;

  /// Speech needed before an end can be detected.
  final double minSpeechSeconds;

  /// Silence that ends the utterance.
  final double endSilenceSeconds;

  /// Speech threshold as a multiple of the noise floor.
  final double ratio;

  /// Lowest speech threshold (RMS, full scale = 1), for a silent room.
  final double minRms;

  int get _frameSamples => math.max(1, (sampleRate * frameSeconds).round());

  final List<int> _pending = [];
  int _frames = 0;
  double _floorSum = 0;
  int _floorFrames = 0;
  double _speech = 0;
  double? _start;
  double? _lastSpeech;

  /// RMS of the latest frame (full scale = 1).
  double rms = 0;

  /// Whether the utterance is over.
  bool ended = false;

  /// Seconds into the audio where speech began (once confirmed).
  double? get speechStart => _speech >= minSpeechSeconds ? _start : null;

  /// Seconds into the audio where the last speech frame ended.
  double? get speechEnd => speechStart == null ? null : _lastSpeech;

  /// Seconds of audio analysed.
  double get elapsed => _frames * _frameSamples / sampleRate;

  /// Meter level 0..1 for the latest frame.
  double get level => math.min(1, math.sqrt(rms) * 2);

  /// Speech threshold in use (null while calibrating).
  double? get threshold => _floorFrames == 0 || elapsed < calibrateSeconds
      ? null
      : math.max(minRms, _floorSum / _floorFrames * ratio);

  /// Feeds raw PCM16 little-endian [bytes]; returns [ended].
  bool add(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _pending.add(data.getInt16(i, Endian.little));
      if (_pending.length == _frameSamples) _frame();
    }
    return ended;
  }

  void _frame() {
    var sum = 0.0;
    for (final s in _pending) {
      sum += (s / 32768) * (s / 32768);
    }
    _pending.clear();
    rms = math.sqrt(sum / _frameSamples);
    final from = elapsed;
    _frames++;
    if (ended) return;
    if (from < calibrateSeconds) {
      _floorSum += rms;
      _floorFrames++;
      return;
    }
    if (rms > threshold!) {
      _start ??= from;
      _speech += frameSeconds;
      _lastSpeech = elapsed;
      return;
    }
    final quiet = elapsed - (_lastSpeech ?? from);
    if (quiet < endSilenceSeconds) return;
    if (_speech >= minSpeechSeconds) {
      ended = true;
    } else {
      // A cough or a click: start over.
      _start = null;
      _speech = 0;
      _lastSpeech = null;
    }
  }
}
