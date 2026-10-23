# Sufler data contract

Every part of the app (importers, rehearsal engine, TTS service, Anki export)
speaks this one shape. Source of truth: `lib/model/`. Change the Dart model and
this file together.

## Script (`lib/model/script.dart`)

```json
{
  "id": "<sha256 of source bytes, hex>",
  "title": "Krasnale (się) rządzą",
  "source": "Krasnale-się-rządzą.pdf",
  "characters": [{"id": "piaskowy-wilk", "name": "Piaskowy Wilk", "aliases": ["Piaksowy Wilk"]}],
  "scenes": [{"id": "scena-1", "title": "Scena 1", "start": 0, "end": 120}],
  "songs":  [{"id": "piosenka-krasnali", "title": "Piosenka Krasnali", "start": 5, "end": 40}],
  "lines": [{
    "index": 7,
    "speakers": ["piaskowy-wilk"],
    "text": "Piaskowe Wilki nie jedzą Krasnali!",
    "kind": "dialogue",
    "sceneId": "scena-1",
    "songId": null,
    "directions": ["(Wzdycha)"]
  }]
}
```

- `lines[i].index == i`. Section `start`/`end` are inclusive line indices.
- A song headed `Piosenka …` starts on its `heading` line. A red passage with
  no such heading is still a song: its section starts on its first lyric
  line, is titled `♪ <that lyric, cut to 40 chars with …>`, and every lyric
  carries its `songId`. A red "X śpiewa piosenkę" intro before it stays a
  `direction` outside the section.
- A line is spoken (`isSpoken`) only when it is not a `direction`/`heading`
  and its `text` has a letter or digit. Importers never emit text without
  one: such a line becomes a `direction` with empty `text`, its leftover
  punctuation kept in `directions` (or dropped, for bare `...`).
- `kind`: `dialogue` | `song` (red text / under a song heading) | `recitation`
  (blue text) | `direction` (stage direction on its own) | `heading`.
- A speech block (speaker heading + text until the next heading) is ONE
  dialogue line. Song and recitation text is split into ONE line per lyric/verse
  line, so each lyric line is cued by the one before it.
- `speakers` holds character ids. Multi-speaker headings ("Błystek, Koszałek,
  Pietrzyk") list every id. Empty = unattributed (chorus lyric).
- Song singers: a title naming one character ("Piosenka Macochy") is sung by
  that character; a title naming a cast-list group ("1. Krasnale:" →
  "Piosenka Krasnali", "Piosenka Krasnali 2"; Polish inflections compared
  by stem, a trailing number ignored) by every member of that group;
  otherwise by the last speaker (or the characters a red "X i Y śpiewają"
  intro names).
- Singer tags inside a song or red run set the speakers of the lyrics that
  follow, until the next tag: "Razem" / "Wszyscy" / "Chór" = every singer of
  that song; an initial ("R.", "Ż.") = the one singer whose name starts with
  it, looked up among the song's singers, then among the scene's speakers
  (several or none: unattributed); joined forms ("R. i L.") combine. A tag
  line is a `direction` with empty `text`, the tag kept in `directions`
  (inside the song section, except a tag before its first lyric); it never
  titles an unheaded song. Outside songs "Wszyscy" stays a speaker heading.
- A closing marker ("Koniec", "Kurtyna") as the document's last line is a
  `direction` with empty `text`, never the last speaker's line.
- Stage directions `( … )` are removed from `text` and kept in `directions`.
  The ellipsis pause marker `/.../` is removed from `text` and NOT kept.
- A structural word on its own line is a `heading` line, never part of the
  speech above it: "Finał", "Epilog", "Prolog" (any case, a trailing `.`/`:`
  dropped) open a scene section titled as written, like `Scena <n>`;
  "Wstęp", "Antrakt", "Akt <n>" (arabic or roman) are headings inside the
  current scene. Inside a sentence ("Finał!", "Akt odwagi") they stay text.
- Scene numbering is kept as written: duplicates and gaps are legal.
- Character and section ids are ASCII slugs (Polish letters folded), unique
  within the script; a duplicate title gets `-2`, `-3` suffixes.

## Role (`lib/model/role.dart`)

`character:<id>`, `song:<id>` or `group:<ids>`. The actor picks any set of
roles; a line is theirs when it is spoken and a role owns it (`isMine`).

- `character:<id>`: every line whose `speakers` contain the id.
- `song:<id>`: every lyric line of that song, regardless of `speakers`.
- `group:<id>+<id>+…`: member ids sorted and joined with `+`; owns every line
  whose `speakers` contain ALL members (the group singing together, alone or
  with others). `group:` (no members) is the chorus: lines with empty
  `speakers`.

Group speakers are derived from the script, not stored in it
(`lib/rehearsal/groups.dart`): ensemble headings (`Wszyscy`, `Razem`, `Chór`,
`Krasnale`, …) and plural headings over numbered members (`Śnieżynki` over
`Śnieżynka 1`, `Śnieżynka 2`) stay `character:` roles listed as groups; any
set of 3+ characters speaking together on 2+ lines (a cast-list group whose
song was attributed to every member) is a `group:` role; unattributed lines
give `group:`. Picking a character suggests (pre-ticks) the groups it belongs
to.

## Script fingerprint (`Script.fingerprint`)

sha256 (hex) of the UTF-8 bytes of, for EVERY line in order, the row
`"${index}\t${kind.name}\t${speakers.join(',')}\t${text}\n"` (the same
formula as the pack manifest's `fingerprint` below). It identifies one exact
parse: any change of a line's index, kind, speakers or text changes it.

## Audio pack (TTS service → app)

A zip named `<script-id>.sufler-audio.zip`:

```
manifest.json   {"scriptId": "...", "engine": "chatterbox-multilingual@<ver>",
                 "voices": {"<character-id>": "<voice-id>"},
                 "fingerprint": "<sha256 hex>",
                 "lines": {"<line-index>": "audio/<line-index>.ogg"}}
audio/<line-index>.ogg   one clip per spoken line, Opus in Ogg, mono 24 kHz
```

`fingerprint` = sha256 (hex) of the UTF-8 bytes of, for EVERY line of the
posted Script in order (spoken or not), the row
`"<index>\t<kind>\t<speakers joined with ','>\t<text>\n"`, where `kind` is the
JSON `kind` string and `text` the line's `text` as sent (`speakers` empty gives
an empty field). The app recomputes it from its own parse and rejects a pack
whose fingerprint differs ("Paczka głosów pochodzi z innej wersji tekstu —
wygeneruj ponownie"); a partial pack with a matching fingerprint is fine. A
pack without `fingerprint` (older service) is accepted with a warning only
when every clip index is a line of the script. Pinned by
`tts/tests/test_fingerprint.py` and `test/audio/pack_check_test.dart` (same
hand-written digest).

Clips exist for every spoken line (the app decides which ones to play), so one
pack serves any role choice. Unattributed song lines use a neutral narrator voice.

Corrections and the pack (`lib/storage/line_edits.dart`): the stored script
is the corrected one, so a correction changes `Script.fingerprint`. Every
correction ("Popraw tekst", or ✎ during rehearsal) therefore re-stamps the
stored pack at once instead of letting the next check refuse it: a pack
stamped for the script before the correction keeps the clips of lines whose
`text` and `speakers` are unchanged (same indices) and is stamped with the
corrected fingerprint; the corrected line's clip is dropped (it says the old
words, or in the old voice). An unstamped pack loses those clips and stays
unstamped; a pack already stamped for another parse is left as it is (and
stays refused). The new clip for a corrected line is an overlay in the same
zip: `audio/<index>.ogg` replaced, `manifest.lines` updated, the fingerprint
unchanged (it already matches). So the overlay plays, re-keys on re-parse and
goes into the Anki export like any clip. Until it exists the line plays with
device TTS ("głos: syntezator do czasu wygenerowania"). A corrected spoken
line with no clip in an existing pack is retried at the next rehearsal and
whenever the PC reports itself back online. Importing the pack zip that was
rendered before a correction again is refused as stale, like a pack from
before a re-parse; "Generuj głosy" renders the corrected script whole.

## Assistant (PC side → app)

`lib/assist/assistant.dart`: `explain(script, index, selection)` returns a
Polish explanation of the selected words in line `index` (meaning in context
plus 2-3 mnemonics); `renderLine(script, index)` returns one clip (Ogg/Opus,
the same format as pack clips) for line `index` as the script has it now, or
null when the PC cannot render it; `pcOnline` reports reachability changes.
The app treats a thrown call as "offline" unless the PC last reported itself
online (then it is the PC's error), waits for `pcOnline` to report `true`
and sends again; queued questions live in memory only (an app restart drops
them, a pending clip is found again from the pack). Without a PC side the
app wires `OfflineAssistant` (never online, every call fails).

## Google Docs proxy (desktop wrapper → web build)

`GET /api/gdoc?id=<doc-id>` on the loopback wrapper (`lib/desktop/`), because
Google sends no CORS headers. Android fetches Google's export directly.

| Status | Body | Meaning |
|---|---|---|
| 200 | the `.docx` bytes | document exported |
| 400 | `{"error": "invalid document id"}` | id is not `[A-Za-z0-9_-]{1,200}` |
| 403 | `{"error": "not_shared"}` | Google answered 401/403/404, or a 200 HTML sign-in page: not shared as "anyone with the link", or gone |
| 502 | `{"error": "<reason>"}` | any other upstream status, or Google unreachable |

The importer (`lib/import/google_doc.dart`) shows the "not shared" message for
403 (and for Google's own 401/404 or a non-zip 200 on Android), and
`Download failed: HTTP <status> (<error>)` for anything else. Pinned end to end
by `test/desktop/gdoc_contract_test.dart`.

## Rehearsal prefs (per script, stored on device)

```json
{"roles": ["character:piaskowy-wilk", "group:blystek+zagiewka"], "speed": 1.0,
 "lineSeconds": {"<line-index>": 4.2}, "recordings": {"<line-index>": "<path>"},
 "knowledge": {"<line-index>": [false, true]},
 "resume": {"label": "Scena 3", "start": 120, "end": 240, "position": 7,
            "mode": "range", "line": 131},
 "rolesAsked": true, "pureRuns": ["scena-3"],
 "notes": {"<line-index>": [{"about": "Wilku", "text": "<explanation>"}]}}
```

- Every field is optional: prefs written by older versions load unchanged.
- `knowledge`: ✓ (`true`) / ✗ per line, oldest first, last 20 kept: only the
  FIRST attempt of each pass (a ✗ is asked again until ✓; retries are not
  stored; same shape). "Only lines I missed" = lines whose last grade is ✗.
- `pureRuns`: scene/song ids walked whole with every own line ✓ first try
  ("Czysty przebieg" badge); never cleared, omitted when empty, kept on re-parse.
- `notes`: every answer of "Zapytaj Claude" about a line, oldest first:
  `about` = the words asked about (a word or its sentence), `text` = the
  answer. Omitted when empty; moved with the line on re-parse like
  `knowledge` (a line that is gone takes its notes into `backup/`). They go on
  the back of the line's Anki card (`<hr>`, then `<b>about</b>: text` each).
- `resume`: the last rehearsal (line range, `mode` `range` or `missed`) and
  the cue position reached; the app offers to continue there. `line` is
  the script line of that cue (its first line, for a run) and is what
  resumes: the position shifts when runs fold into one cue or the setting
  changes. Without `line` (older prefs) the position is read against the
  walk with no runs folded.
- `rolesAsked`: the roles screen was shown once for this script.
- A per-line pause set with −/+ during rehearsal or measured by "Nagraj
  czasy" without audio is a `lineSeconds` entry; a measured take with audio
  is stored as the recording (speech only, so its length + 1 s is the pause)
  and drops that line's `lineSeconds`.
- A whole run recorded in one take ("Nagraj w całości") is stored as one
  recording PER LINE: the take cut at each line's first and last heard word
  (desktop, `words` below) or by syllable shares of its voiced part
  (Android, or an older service without `words`). Same keys and shape as
  any recording; lines that already had one keep it unless the user picks
  "Nadpisz".
- A run learnt as one unit (setting `wholeRuns`) stores its one
  first-attempt grade in `knowledge` for every line of the run.
- Pause precedence: `lineSeconds` > recording (+ 1 s) > estimate > formula.
  The estimate (median seconds per syllable over the recordings, needs >= 3,
  `lib/rehearsal/pace.dart`) is derived on the fly and never stored.

## Re-parse (stored scripts after a parser change)

`parserVersion` (`lib/import/parser_version.dart`) is bumped with every
structuring change. Next to `script/<id>` the device keeps `source/<id>` (the
imported document's bytes), `meta/<id>` (`{"parserVersion": n,
"parseFingerprint": "<fingerprint of the raw parse>"}`) and `edits/<id>` (the
manual corrections: `{"op": "line", "index", "speakers"?, "kind"?,
"text"?, "was"?}` and `{"op": "merge", "from", "into"}`, in order). A text
correction carries the text it replaced in `was`.

When a stored script's `parserVersion` is older (on open, from `source/`) or
the same document is imported again with a different raw fingerprint, the new
parse replaces the old one: lines are aligned old → new (longest common
subsequence of normalised texts, then similar lines inside each gap; text
corrections are undone through their `was`, newest first, before aligning, so
a reworded line still meets its parsed self);
`lineSeconds`, `recordings` (re-keyed to `rec/<id>/<new index>`), `knowledge`,
`notes` and the `resume` range move to the new indices; corrections are replayed (for
scripts stored before the log: merges inferred from aliases); data of lines
that no longer exist is dropped from prefs but kept, with the old script and
prefs, under `backup/<id>/…`. A voice pack stamped for the old parse keeps
only the clips of lines whose text and speakers are unchanged, re-keyed and
re-stamped; an unstamped pack is dropped. Aligned spoken lines whose speakers
or kind now differ are counted in the summary. The app shows one line, e.g. "Zaktualizowano
parsowanie: 2 kwestie przeniesione, 0 utraconych". A script stored without
its document is re-parsed on open from the copy file_picker left in the
Android cache (`<cacheDir>/file_picker/<ms>/<source>` whose sha256 is the
id), which is then kept as `source/<id>`; with no such copy the old parse
stays, silently, and "Narzędzia" offers "Odśwież parsowanie: wskaż plik".

## App settings (device-wide, not per script)

```json
{"version": 2, "visibility": "revealAfter", "selfGrade": false, "loop": false,
 "cleanTarget": 3, "listen": false, "wholeRuns": true, "partnerText": false,
 "lastScriptId": "<script id>"}
```

`wholeRuns` (missing = `true`): runs are one rehearsal step
(`lib/rehearsal/runs.dart`). An own run is a row of the actor's spoken
lines with no partner spoken line between them (directions and headings do
not break it), cut where a song starts or ends and at a scene change: 2+
lines inside a song, 3+ outside. It is said, revealed and graded once (one
countdown = the sum of its lines' pauses; never listened to, so pauses in
it do not end it). A partner run is a row of partner lines with no own line
between them: 2+ inside one song (any singers) or 3+ by the very same
speakers; its lines play back to back as one step. A ✗ replays only the
last line of the step before.

`visibility`: `revealAfter` (learning: hidden while said, then shown and
graded), `hide`, `show` (read-through). Settings without `version` (v1) stored
the old default `show`; it loads as `revealAfter` once. `partnerText` (show
partner lines as text while they play) was added without a version bump:
absent means `false`, so older settings keep partner text hidden. The app opens
`lastScriptId` on start (or the only script, when none is remembered).

## Transcription (TTS service, speech-to-text)

`POST http://127.0.0.1:8791/transcribe?lang=pl` on the voice service (the
desktop wrapper proxies `/api/tts/*` to it). The body is the audio itself, sent
with `Content-Length` (max 32 MiB): WAV PCM 16-bit (any sample rate, mono or
not; 16 kHz mono typical) or Ogg/WebM Opus; ffmpeg decodes and resamples to
mono 16 kHz, so any ffmpeg-readable upload works. `lang` is a 2-3 letter
language code, default `pl`.

```json
{"text": "Piaskowe wilki nie jedzą krasnali.",
 "segments": [{"start": 0.31, "end": 2.40, "text": "Piaskowe wilki nie jedzą krasnali."}],
 "words": [{"start": 0.31, "end": 0.78, "word": "Piaskowe"}, …],
 "speechStart": 0.31, "speechEnd": 2.40,
 "engine": "faster-whisper@1.2.1/large-v3-turbo"}
```

- Times are seconds from the start of the uploaded clip. `speechStart` /
  `speechEnd` are the first word's start and the last word's end (tighter than
  the segment times); VAD drops leading and trailing silence first.
- `words`: every recognised word with its own times (Whisper's word
  timestamps; the word trimmed, punctuation kept). The app cuts a whole
  sung or spoken run into its lines by them; no key (older service) means
  no word times.
- No speech found: `200` with `"text": ""`, `"segments": []`, `"words": []`,
  and
  `"speechStart"` / `"speechEnd"` both `null`.
- `text` is Whisper's own casing and punctuation; compare it normalised
  (lower-case, punctuation dropped), not byte for byte.

| Status | Body | Meaning |
|---|---|---|
| 200 | the object above | transcribed |
| 400 | `{"error": "undecodable audio"}` | empty body or ffmpeg cannot decode it |
| 400 | `{"error": "lang must be ..."}` | malformed `lang` |
| 413 | `{"error": "too big"}` | body over 32 MiB |
| 500 | `{"error": "<reason>"}` | model failed to load or run |
| 503 | `{"error": "no STT"}` | service started without a transcriber |

`GET /health` also reports `"stt": "<engine>"`. The model (faster-whisper
`large-v3-turbo`, CTranslate2 fp16, MIT) loads on the first request in its own
child process and exits after 10 min idle, independently of Chatterbox.
Measured on the RTX 3090 with a ~4 s Polish clip: ~0.2 s warm, ~1.5 s cold
(model load), WER 0.00 on three synthesised sentences, 7.0 GiB of VRAM with
Chatterbox loaded as well.

App side (`lib/audio/transcribe_client.dart`): the desktop build posts each
"Nagraj czasy" / listening take as WAV to `/api/tts/transcribe?lang=pl` and
prefers `speechStart`/`speechEnd` over its own VAD; any status but 200 (404
older service, 503 no STT) or a network error means "no transcript". Android
uses the system recognizer (`speech_to_text`, `pl_PL`) instead; after an
error meaning it cannot work there (network, server, language, audio,
permission) that run falls back to the recorder with VAD only (no
transcript). A take neither path heard is timed by a tap in the walk
(`lineSeconds`, never a recording). A whole-run take is recorded with the
plain recorder (ended by "Skończyłem", never by silence) and, on desktop,
posted the same way (2 min timeout) for its `words`; Android has no route to
the service (it listens on the PC's loopback only), so there a run is always
split by syllables.
