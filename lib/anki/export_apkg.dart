/// Anki export: front = the cue before each of the actor's lines, back =
/// the actor's line and its notes, cue audio from an `AudioPack` when given.
///
/// `exportApkg(script, roles, {audio, notes})` builds the `.apkg` bytes. On
/// Android it writes the collection locally with sqlite3; on web (desktop)
/// sqlite3 does not run, so the deck is derived in the browser and posted to
/// the desktop wrapper's `POST /api/apkg`, which writes it with the same
/// code.
library;

export 'export_apkg_io.dart'
    if (dart.library.js_interop) 'export_apkg_web.dart';
