import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';

/// Progress of a GPU render of every spoken line of a script.
class RenderProgress {
  /// Creates a progress event; [pack] is set on the final event only.
  const RenderProgress({required this.done, required this.total, this.pack});

  /// Lines rendered so far.
  final int done;

  /// Lines to render.
  final int total;

  /// The finished pack (final event only).
  final AudioPack? pack;
}

/// Whether a voice renderer is reachable (desktop wrapper + TTS service).
/// Owned by the desktop/TTS layer; this stub says "no" everywhere.
Future<bool> renderAvailable() async => false;

/// Renders (or fetches the cached) audio pack for [script].
Stream<RenderProgress> renderPack(Script script) =>
    Stream.error(UnimplementedError('renderPack'));
