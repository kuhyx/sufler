# Sufler data contract: on-device state

Part of [DOCS-contract.md](DOCS-contract.md): what the app stores per script
and per device. Source of truth: `lib/model/` and `lib/storage/`.

## Rehearsal prefs (per script, stored on device)

```json
{"roles": ["character:piaskowy-wilk", "group:blystek+zagiewka"], "speed": 1.0,
 "lineSeconds": {"<line-index>": 4.2}, "tapSeconds": {"<line-index>": 3.1},
 "recordings": {"<line-index>": "<path>"},
 "knowledge": {"<line-index>": [false, true]},
 "resume": {"label": "Scena 3", "start": 120, "end": 240, "position": 7,
            "mode": "range", "line": 131, "retry": true},
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
  walk with no runs folded. `retry: true` (omitted otherwise; older prefs
  have none = false): that cue was graded ✗ on its first try and left while
  being asked again; on resume the ✗ stands, so the next ✓ is a retry (not
  stored in `knowledge`, the pass is not clean for `pureRuns`). Kept on
  re-parse.
- `rolesAsked`: the roles screen was shown once for this script.
- A per-line pause set with −/+ during rehearsal or measured by "Nagraj
  czasy" without audio is a `lineSeconds` entry. A time tapped in "Nagraj
  czasy" ("Skończyłem", line shown to tap) is ALSO kept in `tapSeconds` (same
  seconds, same shape; omitted when empty) as a pace sample: −/+, "Ustaw
  pauzę" or "Automatycznie" later change `lineSeconds` only, as they leave a
  recording's sample alone. A measured take with audio
  is stored as the recording (speech only, so its length + 1 s is the pause)
  and drops that line's `lineSeconds`.
- A whole run recorded in one take ("Nagraj w całości") is stored as one
  recording PER LINE: the take cut at each line's first and last heard word
  (desktop, `words` in DOCS-contract-voice.md) or by syllable shares of its voiced part
  (Android, or an older service without `words`). Same keys and shape as
  any recording; lines that already had one keep it unless the user picks
  "Nadpisz".
- A run learnt as one unit (setting `wholeRuns`) stores its one
  first-attempt grade in `knowledge` for every line of the run.
- Pause precedence: `lineSeconds` > recording (+ 1 s) > estimate > formula.
  The estimate (median seconds per syllable over the recordings and the
  `tapSeconds` taps, a line with both counted once by its recording, needs
  >= 3, `lib/rehearsal/pace.dart`) is derived on the fly and never stored.

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
`lineSeconds`, `tapSeconds`, `recordings` (re-keyed to `rec/<id>/<new index>`), `knowledge`,
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

