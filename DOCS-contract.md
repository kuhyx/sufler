# Sufler data contract

Every part of the app (importers, rehearsal engine, TTS service, Anki export)
speaks this one shape. Source of truth: `lib/model/`. Change the Dart model and
these files together.

The contract is split in three files, each under the 250-line cap:

- this file: Script, Role, fingerprint, audio pack, assistant, Google Docs proxy;
- [DOCS-contract-device.md](DOCS-contract-device.md): rehearsal prefs,
  re-parse, app settings;
- [DOCS-contract-voice.md](DOCS-contract-voice.md): transcription, explain +
  render_line.

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
