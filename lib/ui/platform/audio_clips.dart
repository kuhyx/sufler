// coverage:ignore-file
// Platform glue over audioplayers; needs a real audio output. The ordering
// logic (newest request wins) is LatestClipPlayer, tested on its own.
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:sufler/audio/latest_clip.dart';

/// Plays in-memory clips (pack Ogg/Opus, own WAV recordings).
class AudioClips extends LatestClipPlayer {
  /// Plays through one audioplayers player.
  new() : super(_PlayerOutput(AudioPlayer()));
}

class _PlayerOutput implements ClipOutput {
  new(this._player);

  final AudioPlayer _player;

  @override
  Future<void> start(Uint8List bytes, String mimeType) =>
      _player.play(BytesSource(bytes, mimeType: mimeType));

  @override
  Future<void> halt() => _player.stop();

  @override
  Stream<void> get completed => _player.onPlayerComplete;
}
