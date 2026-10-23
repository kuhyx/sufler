// coverage:ignore-file
// Platform glue over `record`; needs a real microphone. The logic (VAD,
// trimming, preferring the recognizer's bounds) is VadTake, tested.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/rehearsal/capture.dart';

/// Turns a take's WAV into a transcript (null: none available).
typedef Transcribe = Future<Transcript?> Function(Uint8List wav);

/// Streams PCM16 mono from the mic, ends the take when [VadTake] hears
/// the end of speech, then optionally asks [transcribe] what was said.
class VadCapture implements SpeechCapture {
  /// Creates the capture; [transcribe] is the desktop voice service.
  new({this.transcribe});

  /// Recognizer for finished takes, if any.
  final Transcribe? transcribe;

  static const _rate = 16000;
  final AudioRecorder _rec = AudioRecorder();
  Completer<void>? _stop;
  bool _cancelled = false;

  @override
  final ValueNotifier<double> level = ValueNotifier(0);

  @override
  Future<CaptureResult?> listen() async {
    if (!await _rec.hasPermission()) return null;
    var rate = _rate;
    await _rec.setOnConfigChanged((c) => rate = c.sampleRate);
    final stop = _stop = Completer<void>();
    _cancelled = false;
    VadTake? take;
    final stream = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _rate,
        numChannels: 1,
      ),
    );
    void end() {
      if (!stop.isCompleted) stop.complete();
    }

    final sub = stream.listen((chunk) {
      final t = take ??= VadTake(rate);
      final over = t.add(chunk);
      level.value = t.endpoint.level;
      if (over) end();
    }, onDone: end);
    await stop.future;
    await _rec.stop();
    await sub.cancel();
    level.value = 0;
    final t = take;
    if (_cancelled || t == null) return null;
    final heard = await transcribe?.call(t.wav());
    final bounded = heard?.speechStart != null && heard?.speechEnd != null;
    return t.result(
      transcript: heard?.text,
      serverStart: bounded ? heard!.speechStart : null,
      serverEnd: bounded ? heard!.speechEnd : null,
    );
  }

  @override
  Future<void> finish() async {
    final s = _stop;
    if (s != null && !s.isCompleted) s.complete();
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await finish();
  }
}
