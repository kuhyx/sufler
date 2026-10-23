import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/role.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/partner_player.dart';
import 'package:sufler/rehearsal/voices.dart';
import 'package:sufler/storage/idb_store.dart';
import 'package:sufler/storage/library.dart';
import 'package:sufler/tts/render_pack.dart';
import 'package:sufler/ui/services.dart';

import '../rehearsal/fake_capture.dart';
import '../rehearsal/fixture.dart';
import '../storage/pack_zip_test.dart' show fixturePackZip;

class FakeFiles implements FileAccess {
  PickedFile? next;
  final saved = <String, Uint8List>{};
  @override
  Future<PickedFile?> pick(List<String> extensions) async => next;
  @override
  Future<void> save(String fileName, Uint8List bytes, String mimeType) async =>
      saved[fileName] = bytes;
}

class FakeRecorder implements Recorder {
  bool recording = false;
  bool allow = true;
  Uint8List? result;
  @override
  Future<bool> start() async => recording = allow;
  @override
  Future<Uint8List?> stop() async {
    recording = false;
    return result;
  }
}

/// TTS that "speaks" for one second of (fake) time; with [fail] it has no
/// voice and every utterance fails at once.
class FakeSpeech implements Speech {
  final said = <String>[];
  bool fail = false;
  @override
  Future<void> speak(String text, Voice voice, double speed) {
    said.add(text);
    if (fail) return Future.error(const SpeechFailure('synthesis-failed'));
    return Future.delayed(const Duration(seconds: 1));
  }

  @override
  Future<void> stop() async {}
}

class FakeClips implements ClipPlayer {
  final played = <String>[];
  @override
  Future<void> play(Uint8List bytes, String mimeType) async =>
      played.add(mimeType);
  @override
  Future<void> stop() async {}
}

/// Direct storage calls from a test body: the widget-test fake clock does
/// not advance while the body awaits, so pump until the call completes.
/// (runAsync would bind the idb database to the real zone and stall the UI.)
extension StorageIo on WidgetTester {
  Future<T> io<T>(Future<T> Function() body) async {
    late T result;
    Object? error;
    var done = false;
    unawaited(
      body().then(
        (v) {
          result = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var i = 0; i < 200 && !done; i++) {
      await pump(const Duration(milliseconds: 10));
    }
    if (error != null) throw error!;
    if (!done) throw StateError('storage call did not complete');
    return result;
  }

  /// Scrolls [finder] into view, taps it and settles.
  Future<void> tapVisible(Finder finder) async {
    // Lazily built list item: scroll the page's main list until it exists,
    // up first (cheap when it is already above), then down.
    for (final delta in [-300.0, 300.0]) {
      if (finder.evaluate().isNotEmpty) break;
      try {
        await scrollUntilVisible(
          finder,
          delta,
          maxScrolls: 20,
          scrollable: find.byType(Scrollable).first,
        );
      } on Object {
        // Not in that direction.
      }
    }
    await ensureVisible(finder);
    await pumpAndSettle();
    await tap(finder);
    await pumpAndSettle();
  }

  /// Pixel 6a portrait: 1080x2400 physical at 2.625 dpr (411x914 logical).
  void usePhone() {
    view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(view.reset);
  }

  /// A wide desktop browser window.
  void useDesktop() {
    view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  }
}

/// Everything faked; the stubs in lib/import, lib/anki, lib/tts are never
/// called.
class TestRig {
  TestRig({String db = 'rig', this.renderable = false})
    : library = ScriptLibrary(IdbStore(idbFactoryMemory, dbName: db));

  final ScriptLibrary library;
  final bool renderable;
  final files = FakeFiles();
  final recorder = FakeRecorder();
  final speech = FakeSpeech();
  final clips = FakeClips();
  final capture = FakeCapture();
  final imported = <String>[];
  final exported = <Set<Role>>[];

  /// What the picker cache holds for any lookup; every lookup's file name.
  Uint8List? pickedCopy;
  final copyLookups = <String>[];
  Script script = fixtureScript();

  Services get services => Services(
    library: library,
    importDocument: ({required fileName, required bytes}) async {
      imported.add(fileName);
      return script;
    },
    importGoogleDoc: (url) async {
      imported.add(url);
      return script;
    },
    exportApkg: (s, roles, {AudioPack? audio}) async {
      exported.add(roles);
      return Uint8List.fromList([9]);
    },
    renderAvailable: () async => renderable,
    renderPack: (s) => Stream.fromIterable([
      const RenderProgress(done: 1, total: 2),
      RenderProgress(
        done: 2,
        total: 2,
        pack: AudioPack.fromZip(
          fixturePackZip(fingerprint: fixtureScript().fingerprint),
        ),
      ),
    ]),
    files: files,
    findPickedCopy: ({required fileName, required id}) async {
      copyLookups.add(fileName);
      return pickedCopy;
    },
    recorder: recorder,
    speech: speech,
    clips: clips,
    capture: capture,
  );
}
