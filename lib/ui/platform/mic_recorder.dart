// coverage:ignore-file
// Platform glue over `record`; needs a real microphone.
import 'dart:async';

import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/ui/services.dart';

/// Streams PCM16 mono from the mic (works the same on Android and web,
/// unlike file recording, which yields a blob URL on web) and wraps it as
/// WAV, so the length is exact and playback works everywhere.
class MicRecorder implements Recorder {
  static const _rate = 16000;
  final AudioRecorder _rec = AudioRecorder();
  final BytesBuilder _buf = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  Completer<void>? _closed;
  // What the platform actually delivers: it may override the request (the
  // WAV header must match or the "recording + 1 s" pause is wrong).
  int _actualRate = _rate;
  int _actualChannels = 1;

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    _buf.clear();
    _actualRate = _rate;
    _actualChannels = 1;
    await _rec.setOnConfigChanged((c) {
      _actualRate = c.sampleRate;
      _actualChannels = c.numChannels;
    });
    final closed = _closed = Completer<void>();
    final stream = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _rate,
        numChannels: 1,
      ),
    );
    _sub = stream.listen(
      _buf.add,
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
    return true;
  }

  @override
  Future<Uint8List?> stop() async {
    await _rec.stop();
    // Let the last chunks arrive, but never hang on a stream that stays open.
    await _closed?.future.timeout(const Duration(seconds: 1), onTimeout: () {});
    await _sub?.cancel();
    _sub = null;
    if (_buf.isEmpty) return null;
    return pcmToWav(
      _buf.takeBytes(),
      sampleRate: _actualRate,
      channels: _actualChannels,
    );
  }
}
