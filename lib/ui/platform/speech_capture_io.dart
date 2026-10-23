// coverage:ignore-file
// Platform glue over speech_to_text; needs a real device recognizer. The
// take logic (speech span from levels, stragglers, which errors mean the
// recognizer is unusable) is RecognizerTake, tested.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/recognizer_take.dart';
import 'package:sufler/ui/platform/vad_capture.dart';

/// Android: the system recognizer (pl_PL) when it works, else the
/// recorder with VAD only. One of them owns the mic per listen.
SpeechCapture openSpeechCapture() => SttCapture();

/// The Android recognizer as a [SpeechCapture]; see [RecognizerTake].
class SttCapture implements SpeechCapture {
  final SpeechToText _stt = SpeechToText();
  final VadCapture _fallback = VadCapture();

  /// Initialised; a failed initialize is retried on the next listen.
  bool _ready = false;

  /// The recognizer reported it cannot work here (no network for it, no
  /// Polish model...): the recorder takes over for the rest of the run.
  bool _unusable = false;

  /// The current listen went through [_fallback].
  bool _viaRecorder = false;
  RecognizerTake? _take;
  Completer<void>? _done;
  Completer<void>? _over;
  bool _cancelled = false;

  /// speech_to_text's pauseFor counts from the start of the listen and is
  /// only reset by recognised words, not by sound: 1.5 s ended the take
  /// before the first words came back. So wait long for the actor to
  /// begin, then shrink to [_endPause] once words arrive.
  static const _waitForWords = Duration(seconds: 6);
  static const _endPause = Duration(milliseconds: 1500);

  /// How long a stopped listen may take to report "done" (its final words
  /// arrive up to the plugin's 2 s final timeout after stop).
  static const _settleFor = Duration(milliseconds: 2500);

  @override
  final ValueNotifier<double> level = ValueNotifier(0);

  Future<bool> _init() async {
    if (_unusable) return false;
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onStatus: _status, onError: _error);
    } on Object catch (e) {
      debugPrint('speech_to_text unavailable: $e');
    }
    return _ready;
  }

  void _status(String s) {
    final take = _take;
    if (take == null) return;
    if (s == SpeechToText.listeningStatus) {
      take.started();
    } else if (take.live && s == SpeechToText.notListeningStatus) {
      _end();
    } else if (take.live && s == SpeechToText.doneStatus) {
      _end();
      _complete(_over);
    }
  }

  void _error(SpeechRecognitionError e) {
    debugPrint('speech_to_text error: ${e.errorMsg}');
    if (recognizerUnusable(e.errorMsg)) _unusable = true;
    if (_take?.live ?? false) {
      _end();
      _complete(_over);
    }
  }

  void _end() => _complete(_done);

  static void _complete(Completer<void>? c) {
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<CaptureResult?> listen() async {
    _viaRecorder = !await _init();
    if (_viaRecorder) {
      _fallback.level.addListener(_mirror);
      try {
        return await _fallback.listen();
      } finally {
        _fallback.level.removeListener(_mirror);
      }
    }
    final take = _take = RecognizerTake();
    final done = _done = Completer<void>();
    final over = _over = Completer<void>();
    _cancelled = false;
    final clock = Stopwatch()..start();
    double now() => clock.elapsedMilliseconds / 1000;
    try {
      await _stt.listen(
        onResult: (r) {
          if (take.words(r.recognizedWords)) _shortenPause();
          if (take.live && r.finalResult) _end();
        },
        onSoundLevelChange: (db) {
          level.value = ((db + 2) / 12).clamp(0, 1);
          take.level(db, now());
        },
        listenOptions: SpeechListenOptions(
          localeId: 'pl_PL',
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: _waitForWords,
          listenFor: const Duration(minutes: 2),
        ),
      );
    } on Object catch (e) {
      debugPrint('speech_to_text listen failed: $e');
      _take = null;
      return null;
    }
    await done.future;
    final elapsed = now();
    await _stt.stop();
    level.value = 0;
    // Let this session finish (final words, its own "done") before the
    // next listen restarts the recognizer: a late final result would
    // otherwise land in the next take, or the restart hit error_busy.
    if (!_cancelled) await over.future.timeout(_settleFor, onTimeout: () {});
    _take = null;
    return _cancelled ? null : take.result(elapsed);
  }

  void _shortenPause() {
    try {
      _stt.changePauseFor(_endPause);
    } on Object catch (_) {
      // Already stopped: nothing left to shorten.
    }
  }

  void _mirror() => level.value = _fallback.level.value;

  @override
  Future<void> finish() async {
    if (_viaRecorder) {
      await _fallback.finish();
    } else {
      _end();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    if (_viaRecorder) {
      await _fallback.cancel();
    } else {
      await _stt.cancel();
      _end();
    }
  }
}
