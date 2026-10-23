import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
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
    required this.recorder,
    required this.speech,
    required this.clips,
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

  /// Microphone.
  final Recorder recorder;

  /// Device TTS.
  final Speech speech;

  /// Clip playback (pack clips and own recordings).
  final ClipPlayer clips;
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

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}
