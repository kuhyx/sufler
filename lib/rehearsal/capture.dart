import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sufler/rehearsal/vad.dart';
import 'package:sufler/rehearsal/wav.dart';

/// One heard line: when speech started and ended (seconds into the take),
/// optionally what was said and the audio of the speech itself.
@immutable
class CaptureResult {
  /// Creates a result.
  const new({
    required this.speechStart,
    required this.speechEnd,
    this.transcript,
    this.audio,
  });

  /// Seconds into the take where speech began.
  final double speechStart;

  /// Seconds into the take where speech ended.
  final double speechEnd;

  /// What the recognizer heard; null when no recognizer was available.
  final String? transcript;

  /// WAV of the speech span only (so its length is the duration); null
  /// when the capture path keeps no audio (Android recognizer).
  final Uint8List? audio;

  /// How long the actor spoke.
  double get durationSeconds => math.max(0, speechEnd - speechStart);
}

/// The microphone as a line listener. One implementation per platform
/// owns the mic, so recording and recognition never fight over it.
abstract interface class SpeechCapture {
  /// Live input level 0..1 for a meter.
  ValueListenable<double> get level;

  /// Listens until the actor stops speaking (end of speech detected) or
  /// [finish] is called. Null when the mic is unavailable, nothing was
  /// said, or [cancel] was called.
  Future<CaptureResult?> listen();

  /// Ends the current [listen] now, keeping what was heard.
  Future<void> finish();

  /// Abandons the current [listen]; it completes with null.
  Future<void> cancel();
}

/// Accumulates PCM16 mono for one take and runs [SpeechEndpoint] over it:
/// the platform-independent half of a recording [SpeechCapture].
class VadTake {
  /// Starts an empty take at [sampleRate].
  new(this.sampleRate) : endpoint = SpeechEndpoint(sampleRate: sampleRate);

  /// Samples per second.
  final int sampleRate;

  /// End-of-speech detector.
  final SpeechEndpoint endpoint;

  final BytesBuilder _pcm = BytesBuilder(copy: false);

  /// Adds a chunk; returns true once speech has ended.
  bool add(Uint8List chunk) {
    _pcm.add(chunk);
    return endpoint.add(chunk);
  }

  /// The whole take as WAV (what a transcriber is sent).
  Uint8List wav() => pcmToWav(_pcm.toBytes(), sampleRate: sampleRate);

  /// The result, preferring a recognizer's [serverStart]/[serverEnd] over
  /// the detector's; null when no speech was found by either.
  CaptureResult? result({
    String? transcript,
    double? serverStart,
    double? serverEnd,
  }) {
    final start = serverStart ?? endpoint.speechStart;
    final end = serverEnd ?? endpoint.speechEnd ?? endpoint.elapsed;
    if (start == null || end <= start) return null;
    return CaptureResult(
      speechStart: start,
      speechEnd: end,
      transcript: transcript,
      audio: trimWav(wav(), start, end),
    );
  }
}
