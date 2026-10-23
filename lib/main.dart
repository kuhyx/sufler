// coverage:ignore-file
// Bootstrap only: wiring that cannot be exercised without a real app host.
import 'package:flutter/material.dart';
import 'package:sufler/anki/export_apkg.dart';
import 'package:sufler/assist/open_assistant.dart';
import 'package:sufler/import/import_document.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/storage/open_store.dart';
import 'package:sufler/tts/render_pack.dart';
import 'package:sufler/ui/app.dart';
import 'package:sufler/ui/platform/audio_clips.dart';
import 'package:sufler/ui/platform/mic_recorder.dart';
import 'package:sufler/ui/platform/picked_copies.dart';
import 'package:sufler/ui/platform/platform_files.dart';
import 'package:sufler/ui/platform/speech_capture.dart';
import 'package:sufler/ui/platform/tts_speech.dart';
import 'package:sufler/ui/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await openStore();
  final library = ScriptLibrary(store);
  runApp(
    SuflerApp(
      services: Services(
        library: library,
        importDocument: importDocument,
        importGoogleDoc: importGoogleDoc,
        exportApkg: exportApkg,
        renderAvailable: renderAvailable,
        renderPack: renderPack,
        files: PlatformFiles(),
        findPickedCopy: findPickedCopy,
        recorder: MicRecorder(),
        speech: TtsSpeech(),
        clips: AudioClips(),
        capture: openSpeechCapture(),
        transcribe: openTranscriber(),
        assistant: openAssistant(store),
        pcSession: openPcSession(),
      ),
    ),
  );
}
