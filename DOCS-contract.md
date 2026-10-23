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

`character:<id>` or `song:<id>`. The actor picks any set of roles; a line is
theirs when a role owns it (`isMine`). Picking a song makes every lyric line of
that song theirs, regardless of `speakers`.

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
whose fingerprint differs. Pinned by `tts/tests/test_fingerprint.py`.

Clips exist for every spoken line (the app decides which ones to play), so one
pack serves any role choice. Unattributed song lines use a neutral narrator voice.

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
{"roles": ["character:piaskowy-wilk"], "speed": 1.0,
 "lineSeconds": {"<line-index>": 4.2}, "recordings": {"<line-index>": "<path>"}}
```

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
 "speechStart": 0.31, "speechEnd": 2.40,
 "engine": "faster-whisper@1.2.1/large-v3-turbo"}
```

- Times are seconds from the start of the uploaded clip. `speechStart` /
  `speechEnd` are the first word's start and the last word's end (tighter than
  the segment times); VAD drops leading and trailing silence first.
- No speech found: `200` with `"text": ""`, `"segments": []`, and
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
