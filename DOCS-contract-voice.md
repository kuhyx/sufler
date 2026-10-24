# Sufler data contract: voice service

Part of [DOCS-contract.md](DOCS-contract.md): speech-to-text and the
assistant endpoints of the PC voice service (`tts/`).

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
(`lineSeconds` + `tapSeconds`, never a recording). A whole-run take is recorded with the
plain recorder (ended by "Skończyłem", never by silence) and, on desktop,
posted the same way (2 min timeout) for its `words`; Android has no route to
the service (it listens on the PC's loopback only), so there a run is always
split by syllables.

## Assistant: explain + render_line (voice service; RTDB relay on Android)

`POST /explain` `{selection, line, before, after}` -> `{"text"}` and
`POST /render_line` `{script, index}` -> `audio/ogg` on the voice service
(desktop through `/api/tts/*`); Android sends the same bodies through
`sufler/requests/{rid}` -> `sufler/results/{rid}` in RTDB. Shapes, statuses,
relay rules and credentials: `DOCS-relay.md`. Dart: `lib/assist/`.
