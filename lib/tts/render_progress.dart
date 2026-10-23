import 'package:sufler/audio/audio_pack.dart';

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

/// The voice service (or the wrapper in front of it) refused or failed.
class RenderException implements Exception {
  /// Creates the exception with a human-readable [message].
  const RenderException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'RenderException: $message';
}
