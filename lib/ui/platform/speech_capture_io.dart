// coverage:ignore-file
// Platform glue over speech_to_text; needs a real device recognizer.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/ui/platform/vad_capture.dart';

/// Android: the on-device recognizer (pl_PL) when the phone has one, else
/// the recorder with VAD only. One of them owns the mic per listen.
SpeechCapture openSpeechCapture() => SttCapture();

/// The Android recognizer as a [SpeechCapture]. It keeps no audio, so a
/// take's start/end come from its sound-level callbacks: the first 0.5 s
/// set the noise floor, speech is anything 4 dB above it.
class SttCapture implements SpeechCapture {
  final SpeechToText _stt = SpeechToText();
  final VadCapture _fallback = VadCapture();
  bool? _ready;
  Completer<void>? _done;
  bool _cancelled = false;

  static const _calibrate = Duration(milliseconds: 500);
  static const _aboveFloorDb = 4.0;

  @override
  final ValueNotifier<double> level = ValueNotifier(0);

  Future<bool> _init() async {
    try {
      return _ready ??= await _stt.initialize(
        onStatus: (s) {
          if (s == SpeechToText.doneStatus ||
              s == SpeechToText.notListeningStatus) {
            _end();
          }
        },
        onError: (_) => _end(),
      );
    } on Object catch (e) {
      debugPrint('speech_to_text unavailable: $e');
      return _ready = false;
    }
  }

  void _end() {
    final d = _done;
    if (d != null && !d.isCompleted) d.complete();
  }

  @override
  Future<CaptureResult?> listen() async {
    if (!await _init()) {
      _fallback.level.addListener(_mirror);
      try {
        return await _fallback.listen();
      } finally {
        _fallback.level.removeListener(_mirror);
      }
    }
    final done = _done = Completer<void>();
    _cancelled = false;
    final clock = Stopwatch()..start();
    var floorSum = 0.0;
    var floorN = 0;
    double? start;
    double? end;
    var text = '';
    double now() => clock.elapsedMilliseconds / 1000;
    await _stt.listen(
      onResult: (r) {
        text = r.recognizedWords;
        if (r.finalResult) _end();
      },
      onSoundLevelChange: (db) {
        level.value = ((db + 2) / 12).clamp(0, 1);
        if (clock.elapsed < _calibrate) {
          floorSum += db;
          floorN++;
        } else if (db > (floorN == 0 ? 0 : floorSum / floorN) + _aboveFloorDb) {
          start ??= now();
          end = now();
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: 'pl_PL',
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        pauseFor: const Duration(milliseconds: 1500),
        listenFor: const Duration(minutes: 2),
      ),
    );
    await done.future;
    await _stt.stop();
    level.value = 0;
    final elapsed = now();
    if (_cancelled || (text.isEmpty && start == null)) return null;
    return CaptureResult(
      speechStart: start ?? 0,
      speechEnd: end ?? elapsed,
      transcript: text,
    );
  }

  void _mirror() => level.value = _fallback.level.value;

  @override
  Future<void> finish() async {
    if (_ready ?? false) {
      _end();
    } else {
      await _fallback.finish();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (_ready ?? false) {
      await _stt.cancel();
      _end();
    } else {
      await _fallback.cancel();
    }
  }
}
