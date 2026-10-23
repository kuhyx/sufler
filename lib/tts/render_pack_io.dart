import 'package:sufler/model/script.dart';
import 'package:sufler/tts/render_progress.dart';

/// Whether a voice renderer is reachable. Never on Android: rendering needs
/// the desktop GPU service.
Future<bool> renderAvailable() async => false;

/// Rendering is desktop-only; packs reach the phone as files.
Stream<RenderProgress> renderPack(Script script) => Stream.error(
  UnsupportedError('voice rendering runs on the desktop app only'),
);
