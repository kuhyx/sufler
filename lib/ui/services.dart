import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sufler/assist/assistant.dart';
import 'package:sufler/assist/pc_session.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/audio/transcribe_client.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/capture.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/tts/render_pack.dart';

/// Imports a dropped document (signature of `importDocument`).
typedef DocImporter = Future<Script> Function({
  required String fileName,
  required Uint8List bytes,
});

/// Imports a Google Docs share link (signature of `importGoogleDoc`).
typedef UrlImporter = Future<Script> Function(String url);

/// Builds an Anki deck (signature of `exportApkg`).
typedef ApkgExporter = Future<Uint8List> Function(
  Script script,
  Set<Role> roles, {
  AudioPack? audio,
});

/// Finds a kept copy of document [fileName] whose content hash is [id]
/// (the file picker's cache on Android); null when there is none.
typedef CopyFinder = Future<Uint8List?> Function({
  required String fileName,
  required String id,
});

/// A file the user picked.
typedef PickedFile = ({String name, Uint8List bytes});

/// File dialogs: open, and save/share.
abstract interface class FileAccess {
  /// Lets the user pick one file with one of [extensions]; null = cancelled.
  Future<PickedFile?> pick(List<String> extensions);

  /// Hands [bytes] to the user: share sheet on Android, download on web.
  Future<void> save(String fileName, Uint8List bytes, String mimeType);
}

/// The microphone for "record me".
abstract interface class Recorder {
  /// Starts recording; false when permission is denied.
  Future<bool> start();

  /// Stops and returns the recording as WAV bytes (null if nothing).
  Future<Uint8List?> stop();
}

/// Everything the UI talks to outside itself. `main.dart` wires the real
/// implementations; widget tests wire fakes.
class Services {
  /// Creates the bundle.
  const new({
    required this.library,
    required this.importDocument,
    required this.importGoogleDoc,
    required this.exportApkg,
    required this.renderAvailable,
    required this.renderPack,
    required this.files,
    required this.findPickedCopy,
    required this.recorder,
    required this.speech,
    required this.clips,
    required this.capture,
    this.transcribe,
    this.assistant,
    this.pcSession,
  });

  /// On-device persistence.
  final ScriptLibrary library;

  /// Document importer.
  final DocImporter importDocument;

  /// Google Docs importer.
  final UrlImporter importGoogleDoc;

  /// Anki exporter.
  final ApkgExporter exportApkg;

  /// Whether a voice renderer is reachable.
  final Future<bool> Function() renderAvailable;

  /// Voice renderer.
  final Stream<RenderProgress> Function(Script script) renderPack;

  /// File dialogs.
  final FileAccess files;

  /// Earlier picked documents still on the device.
  final CopyFinder findPickedCopy;

  /// Microphone.
  final Recorder recorder;

  /// Device TTS.
  final Speech speech;

  /// Clip playback (pack clips and own recordings).
  final ClipPlayer clips;

  /// The microphone as a line listener (timing walk, listening rehearsal).
  final SpeechCapture capture;

  /// Speech-to-text with word times for whole-run takes (desktop voice
  /// service); null where there is none (Android).
  final Transcribe? transcribe;

  /// The PC: explain a selection, re-render one line's clip (desktop:
  /// the wrapper; Android: the Firebase relay); null in tests that skip it.
  final Assistant? assistant;

  /// The phone's sign-in for the relay; null on desktop (no sign-in).
  final PcSession? pcSession;
}

/// Makes [Services] available below it.
class ServicesScope extends InheritedWidget {
  /// Provides [services] to [child].
  const new({required this.services, required super.child, super.key});

  /// The services.
  final Services services;

  /// The nearest services.
  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()!.services;

  /// The nearest services, or null outside a [ServicesScope].
  static Services? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()?.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}
