# Assistant endpoints and the phone relay

The app asks "Claude on the PC" to explain a selected word or sentence of a
line, and has a line's voice clip re-rendered right after its text was
edited. Dart: `lib/assist/` (`Assistant`). Desktop (web) posts to the voice
service through the wrapper's `/api/tts/*` proxy (`HttpAssistant`); Android
cannot reach the PC's loopback, so it goes through Firebase RTDB
(`RelayAssistant`), the same request/result pattern as tutor's relay
(`~/src/tutor/DOCS-relay.md`). The PC side: `tts/sufler_tts/assist.py`
(one core for both doors), `explain.py`, `relay/`.

## `POST /explain`

```json
{"scriptId": "abc123", "title": "Krasnale (się) rządzą", "selection": "na bakier",
 "line":   {"index": 7, "speakers": ["Królowa"], "text": "Czapkę nosisz na bakier!"},
 "before": [{"speakers": ["Piaskowy Wilk"], "text": "Dzień dobry."}],
 "after":  [{"speakers": [], "text": "La la la."}]}
```

- `speakers` are display names (character `name`, the id when unknown).
  `before`: the nearest 3 spoken lines before the line, oldest first;
  `after`: the next spoken line. Missing `before`/`after`/`speakers`/`title`
  are fine (RTDB drops empty lists); more context is cut to 3 / 1.
- Answer `200 {"text": "..."}`: Polish, at most ~150 words: one paragraph on
  the meaning in context, then 2-3 numbered mnemonics.
- One headless call: `~/.local/bin/claude -p --model sonnet` (override
  `SUFLER_CLAUDE_BIN`), 90 s timeout, isolated like book-guard's grader
  (`--setting-sources ""`, `--tools ""`, `--strict-mcp-config`,
  `--no-session-persistence`, `cwd=/`): no hooks, no CLAUDE.md, no tools.
  Prompt: `tts/sufler_tts/explain_prompt.txt` (system part, `---USER---`,
  user template). Measured 2026-10-23: 6-11 s, ~105 words.

| Status | Body | Meaning |
|---|---|---|
| 200 | `{"text": "..."}` | explained |
| 400 | `{"error": "<reason>"}` | malformed body (empty selection, over 1000 chars, ...) |
| 503 | `{"error": "<reason>"}` | claude missing, timed out, out of usage, or no answer |

## `POST /render_line`

`{"script": <bare Script JSON, as for /render>, "index": <line index>}` ->
`200 audio/ogg`: the clip of that line's CURRENT text, same format as pack
clips (Opus in Ogg, mono 24 kHz). Voices come from the PC's finished pack of
that script id (`manifest.voices`, overrides it was rendered with included),
the default assignment for anyone it lacks, so the clip matches the pack.
The clip goes through the same cache as packs (the next pack render reuses
it) and runs on the pack engine between pack clips, never behind a whole
pack job. `400 {"error"}`: malformed, no such line, or a line with nothing
to say (direction, heading, only stage directions). `500 {"error"}`: the
engine failed. The app (`renderLine`) treats anything but 200 as null.

## Relay (RTDB, Android only)

Under `/sufler` in the shared kuhy-syncs database (rules: the sync uid only):

```
sufler/requests/{rid}   {"kind": "explain" | "render_line",
                         "payload": "<the HTTP body above, JSON-encoded>",
                         "deviceId": "<phone install uuid>",
                         "ts": {".sv": "timestamp"}}
sufler/results/{rid}    {"ok": true, "text": "..."}            (explain)
                        {"ok": true, "audioB64": "<ogg, base64>"} (render_line)
                        {"ok": false, "error": "<reason>"}
                        + "at": <server ms>
sufler/presence/{pc}    {"beat": <server ms>, "host", "pid", "started", "version"}
sufler/clients/{dev}    {"seen": <server ms>}   (the phone's server-clock probe)
```

- `rid`: 22 random url-safe chars (`[A-Za-z0-9_-]{16,64}` accepted).
  `payload` is a string because RTDB drops nulls and empty lists inside
  objects (`songId: null`, `speakers: []`, a script with no songs).
- Phone (`lib/assist/relay_assistant.dart`): PUT the request, poll
  `results/{rid}` every 1 s, delete the result once read. Deadlines:
  explain 150 s ("PC nie odpowiada"), clip 180 s (null); on a deadline the
  request is deleted. `pcOnline`: every 20 s while listened to, PUT
  `clients/{dev}/seen` = server time and compare it with each
  `presence/*.beat`: online when one beat is under 75 s old. Server time
  against server time; the phone's own clock is never used.
- PC (`tts/sufler_tts/relay/`, in the voice service process): an SSE stream
  of `requests` is only a doorbell (any `put`/`patch` rescans the node, as
  does a 60 s timer, so a dropped stream loses nothing); requests run on two
  threads, so an explanation never waits behind a clip. A rid that already
  has a result is never re-run. A request whose `ts` is over 10 min old
  (server time, skew measured by the beat) or whose rid is malformed is
  deleted unanswered: no Claude call for an ask the phone gave up on.
  Beat every 30 s; the beat is deleted on a clean stop (SIGTERM).
  Results and requests older than 24 h are deleted every 10 min.
- Errors never carry the URL (`?auth=<idToken>` is in it), only method,
  path and status.

## Credentials

- PC: `~/.config/crdt-sync/firebase.json` (URL, API key) plus sufler's own
  session `~/.config/sufler/firebase_auth.json`, seeded ONCE, interactively:
  `cd ~/src/utils/crdt-sync && python3 -m tool.seed_session --client-id ...
  --client-secret ... --app sufler` (tutor's `relay/config.py` pattern;
  `--app` takes only names in that repo's `tool/_seeded_apps.py`
  `DEFAULT_APPS`, so `sufler` must be added there first).
  No config or no session: the service logs `relay off: <why> (HTTP only)`
  and serves HTTP as before. `SUFLER_RELAY=0` turns the relay off.
  The device id is `~/.local/share/sufler/device_id` (crdt_sync format).
- Phone: Ustawienia próby -> "Połącz z PC" (also offered on the first
  request): Google sign-in with the project's Web client id as audience,
  the expected-uid guard, the refresh token in the Android keystore
  (`flutter_secure_storage`), as tutor's app does. Through
  `google_sign_in_android` + the platform interface, never the
  `google_sign_in` app package: its web plugin loads Google's script at
  startup, and the desktop build starts offline. Needs the Android OAuth
  client for `com.kuhy.sufler` + the release SHA-1:
  `scripts/register_oauth_client.sh` (no Google API exists for it).
  The device id is a uuid4 in the app's store (`device/id`).
- Build: the Firebase identifiers are compiled from the gitignored
  `lib/assist/firebase_local.dart`; write it with
  `dart run tool/write_firebase_config.dart` (CI: `--placeholder`, the
  relay then reports "not configured"). The release workflow writes it from
  the `SUFLER_FIREBASE_JSON` secret (firebase.json + `webClientId`).
