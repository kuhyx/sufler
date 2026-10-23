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
- `kind`: `dialogue` | `song` (red text / under a song heading) | `recitation`
  (blue text) | `direction` (stage direction on its own) | `heading`.
- A speech block (speaker heading + text until the next heading) is ONE
  dialogue line. Song and recitation text is split into ONE line per lyric/verse
  line, so each lyric line is cued by the one before it.
- `speakers` holds character ids. Multi-speaker headings ("Błystek, Koszałek,
  Pietrzyk") list every id. Empty = unattributed (chorus lyric).
- Stage directions `( … )` are removed from `text` and kept in `directions`.
  The ellipsis pause marker `/.../` is removed from `text` and NOT kept.
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
                 "lines": {"<line-index>": "audio/<line-index>.ogg"}}
audio/<line-index>.ogg   one clip per spoken line, Opus in Ogg, mono 24 kHz
```

Clips exist for every spoken line (the app decides which ones to play), so one
pack serves any role choice. Unattributed song lines use a neutral narrator voice.

## Rehearsal prefs (per script, stored on device)

```json
{"roles": ["character:piaskowy-wilk"], "speed": 1.0,
 "lineSeconds": {"<line-index>": 4.2}, "recordings": {"<line-index>": "<path>"}}
```
