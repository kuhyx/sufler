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
  new(this.store);

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
    await _updates[id]; // read after pending updates, never before
    return await _readPrefs(id);
  }

  Future<RehearsalPrefs> _readPrefs(String id) async {
    final json = await store.readJson(_prefs(id));
    return json == null
        ? const RehearsalPrefs()
        : RehearsalPrefs.fromJson(json);
  }

  /// Saves prefs of script [id].
  Future<void> savePrefs(String id, RehearsalPrefs prefs) =>
      store.writeJson(_prefs(id), prefs.toJson());

  /// Reads, changes and saves prefs of script [id] in one step, so screens
  /// holding an older copy never overwrite fields they did not touch.
  /// Updates of one script run one after another (a grade and a position
  /// saved in the same instant must not both read the old prefs).
  Future<RehearsalPrefs> updatePrefs(
    String id,
    RehearsalPrefs Function(RehearsalPrefs) change,
  ) {
    Future<RehearsalPrefs> run() async {
      final next = change(await _readPrefs(id));
      await savePrefs(id, next);
      return next;
    }

    final result = (_updates[id] ?? Future.value()).then((_) => run());
    _updates[id] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  final Map<String, Future<void>> _updates = {};

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
    await updatePrefs(
      id,
      (p) => p.copyWith(recordings: {...p.recordings, index: key}),
    );
    return key;
  }

  /// Stores a timed take of line [index]. With [audio] (the speech span
  /// only) it becomes the line's recording, so the pause is its length
  /// + 1 s, and a manual override is dropped (the last action wins).
  /// Without audio the pause is set to [seconds] + 1 s directly.
  Future<void> saveTake(
    String id,
    int index, {
    required double seconds,
    Uint8List? audio,
  }) async {
    if (audio != null) await saveRecording(id, index, audio);
    await updatePrefs(id, (p) {
      final map = {...p.lineSeconds}..remove(index);
      if (audio == null) map[index] = ((seconds + 1) * 10).round() / 10;
      return p.copyWith(lineSeconds: map);
    });
  }

  /// The recording stored under [key], or null.
  Future<Uint8List?> loadRecording(String key) => store.readBytes(key);

  /// Removes the recording of line [index] of script [id].
  Future<void> deleteRecording(String id, int index) async {
    final key = (await loadPrefs(id)).recordings[index];
    if (key != null) await store.delete(key);
    await updatePrefs(
      id,
      (p) => p.copyWith(recordings: {...p.recordings}..remove(index)),
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

  /// Remembers [id] as the script to open on the next start.
  Future<void> rememberScript(String id) async {
    final s = await loadSettings();
    if (s.lastScriptId != id) {
      await saveSettings(s.copyWith(lastScriptId: id));
    }
  }

  /// The script to open on start: the last one opened, or the only one
  /// (libraries from before "last script" was stored). Null: library.
  Future<String?> startScriptId() async {
    final last = (await loadSettings()).lastScriptId;
    if (last != null && await store.readJson(_script(last)) != null) {
      return last;
    }
    final ids = await store.keys('script/');
    return ids.length == 1 ? ids.single.substring('script/'.length) : null;
  }
}
