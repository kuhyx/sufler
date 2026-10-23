import 'dart:math' as math;
import 'dart:typed_data';

const _header = 44;

/// Wraps raw little-endian PCM16 [pcm] in a WAV (RIFF) container, so the
/// "record me" clip plays back everywhere and its length is exact.
Uint8List pcmToWav(Uint8List pcm, {required int sampleRate, int channels = 1}) {
  final out = Uint8List(_header + pcm.length);
  final b = ByteData.sublistView(out);
  void tag(int at, String s) => out.setRange(at, at + 4, s.codeUnits);
  tag(0, 'RIFF');
  b.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b
    ..setUint32(16, 16, Endian.little) // fmt chunk size
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * channels * 2, Endian.little) // byte rate
    ..setUint16(32, channels * 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  b.setUint32(40, pcm.length, Endian.little);
  out.setRange(_header, out.length, pcm);
  return out;
}

/// Duration of a WAV made by [pcmToWav]; 0 for anything unreadable.
double wavSeconds(Uint8List wav) {
  if (wav.length < _header) return 0;
  final b = ByteData.sublistView(wav);
  final byteRate = b.getUint32(28, Endian.little);
  if (byteRate == 0) return 0;
  return b.getUint32(40, Endian.little) / byteRate;
}

/// The part of WAV [wav] (made by [pcmToWav]) from [start] to [end]
/// seconds, as a new WAV; clamped to the audio, whole frames only.
Uint8List trimWav(Uint8List wav, double start, double end) {
  final b = ByteData.sublistView(wav);
  final rate = b.getUint32(24, Endian.little);
  final block = b.getUint16(32, Endian.little);
  final frames = b.getUint32(40, Endian.little) ~/ block;
  int at(double s) => (s * rate).round().clamp(0, frames);
  final from = _header + at(start) * block;
  final to = _header + math.max(at(start), at(end)) * block;
  return pcmToWav(
    wav.sublist(from, to),
    sampleRate: rate,
    channels: block ~/ 2,
  );
}
