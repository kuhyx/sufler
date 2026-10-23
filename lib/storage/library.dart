import 'package:flutter/foundation.dart';
import 'package:sufler/audio/audio_pack.dart';
import 'package:sufler/model/script.dart';
import 'package:sufler/rehearsal/wav.dart';
import 'package:sufler/storage/prefs.dart';
import 'package:sufler/storage/store.dart';

/// Everything the app keeps on the device, on top of a [Store]:
/// scripts, per-script prefs, audio packs, own recordings, app settings.
class ScriptLibrary {
  /// Wraps [store].
  ScriptLibrary(this.store);

  /// Backing store.
  final Store store;

  static String _script(String id) => 'script/$id';
  static String _prefs(String id) => 'prefs/$id';
  static String _pack(String id) => 'pack/$id';
  static String _recDir(String id) => 'rec/$id/';
  static const _settings = 'settings';

  /// Every imported script, sorted by title.
  Future<List<Script>> scripts() async {
    final out = <Script>[];
    for (final key in await store.keys('script/')) {
      final json = await store.readJson(key);
      if (json != null) out.add(Script.fromJson(json));
    }
    return out..sort((a, b) => a.title.compareTo(b.title));
  }

  /// The script with [id], or null.
  Future<Script?> loadScript(String id) async {
    final json = await store.readJson(_script(id));
    return json == null ? null : Script.fromJson(json);
  }

  /// Saves (or replaces, e.g. after corrections) [script].
  Future<void> saveScript(Script script) =>
      store.writeJson(_script(script.id), script.toJson());

  /// Deletes a script with its prefs, pack and recordings.
  Future<void> deleteScript(String id) async {
    await store.delete(_script(id));
    await store.delete(_prefs(id));
    await store.delete(_pack(id));
    for (final key in await store.keys(_recDir(id))) {
      await store.delete(key);
    }
  }

  /// Prefs of script [id] (defaults when none saved).
  Future<RehearsalPrefs> loadPrefs(String id) async {
    final json = await store.readJson(_prefs(id));
    return json == null
        ? const RehearsalPrefs()
        : RehearsalPrefs.fromJson(json);
  }

  /// Saves prefs of script [id].
  Future<void> savePrefs(String id, RehearsalPrefs prefs) =>
      store.writeJson(_prefs(id), prefs.toJson());

  /// Stores an audio pack zip for script [id].
  Future<void> savePack(String id, Uint8List zip) =>
      store.writeBytes(_pack(id), zip);

  /// The stored pack of script [id]; null when none or unreadable.
  Future<AudioPack?> loadPack(String id) async {
    final bytes = await store.readBytes(_pack(id));
    if (bytes == null) return null;
    try {
      return AudioPack.fromZip(bytes);
    } on Object catch (e) {
      debugPrint('stored pack $id unreadable: $e');
      return null;
    }
  }

  /// Stores the actor's own WAV for line [index] and records its key in
  /// the prefs. Returns the key.
  Future<String> saveRecording(String id, int index, Uint8List wav) async {
    final key = '${_recDir(id)}$index';
    await store.writeBytes(key, wav);
    final prefs = await loadPrefs(id);
    await savePrefs(
      id,
      prefs.copyWith(recordings: {...prefs.recordings, index: key}),
    );
    return key;
  }

  /// The recording stored under [key], or null.
  Future<Uint8List?> loadRecording(String key) => store.readBytes(key);

  /// Removes the recording of line [index] of script [id].
  Future<void> deleteRecording(String id, int index) async {
    final prefs = await loadPrefs(id);
    final key = prefs.recordings[index];
    if (key != null) await store.delete(key);
    await savePrefs(
      id,
      prefs.copyWith(recordings: {...prefs.recordings}..remove(index)),
    );
  }

  /// Line index -> recording length in seconds, for timing.
  Future<Map<int, double>> recordingSeconds(RehearsalPrefs prefs) async {
    final out = <int, double>{};
    for (final e in prefs.recordings.entries) {
      final wav = await store.readBytes(e.value);
      if (wav != null) out[e.key] = wavSeconds(wav);
    }
    return out;
  }

  /// App-wide settings (defaults when none saved).
  Future<AppSettings> loadSettings() async {
    final json = await store.readJson(_settings);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  /// Saves app-wide settings.
  Future<void> saveSettings(AppSettings settings) =>
      store.writeJson(_settings, settings.toJson());
}
