import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sufler/rehearsal/capture.dart';

/// A take of [seconds] of speech starting 0.5 s in, heard as [text].
CaptureResult take(double seconds, [String? text]) =>
    CaptureResult(speechStart: 0.5, speechEnd: 0.5 + seconds, transcript: text);

/// A microphone the test drives: [hear] ends the pending [listen].
class FakeCapture implements SpeechCapture {
  @override
  final ValueNotifier<double> level = ValueNotifier(0);

  /// Calls to [listen] so far.
  int listens = 0;

  /// What [finish] makes the pending listen return.
  CaptureResult? onFinish;

  /// Takes handed out automatically, one per [listen], before any [hear].
  final List<CaptureResult?> queue = [];

  Completer<CaptureResult?>? _pending;

  /// Whether a [listen] is waiting.
  bool get listening => _pending != null;

  @override
  Future<CaptureResult?> listen() {
    listens++;
    if (queue.isNotEmpty) return Future.value(queue.removeAt(0));
    return (_pending = Completer<CaptureResult?>()).future;
  }

  /// The actor stopped speaking: the pending listen ends with [result].
  void hear(CaptureResult? result) {
    final p = _pending;
    _pending = null;
    p?.complete(result);
  }

  @override
  Future<void> finish() async => hear(onFinish);

  @override
  Future<void> cancel() async => hear(null);
}
