# FEATURES: sufler

> Feature map + core-flow ground truth (skill: `e2e-ground-truth`). Keep it
> current: a user-visible change updates its row in the same commit. "How to
> reach it" is a path a driver can follow; "expected outcome" is something a
> check can observe.

- **Primary targets:** Android (`com.kuhy.sufler`) and desktop (Flutter web
  build in a Chrome `--app` window, served by the loopback wrapper on
  `127.0.0.1:8792`, `/api/tts/*` proxied to the voice service on `:8791`).
  The flows below cover the **desktop** target.
- **Driver:** nested Xephyr `:79` + scratch Chromium over CDP
  (`scripts/e2e_desktop.sh`, helpers in `scripts/e2e/`). Never kuhy's `:0`,
  never the real profile `~/.local/share/sufler/chrome-profile`.
- **Run:** `scripts/e2e_desktop.sh build` (once per change), `up`, then
  `F1` .. `F6` (one per call, each < 60 s, F2-F6 need F1's import), `down`.
  After a wrapper-only rebuild: `scripts/e2e_desktop.sh wrapper`.
- **Role:** `E2E_ROLE` = character id kuhy plays, default `zagiewka`
  (Żagiewka); `E2E_ROLE=piaskowy-wilk` is kept green too.
- **Input:** a real play, `SUFLER_SCRIPT_PDF` (default `private/krasnale.pdf`,
  never committed), and for F6 its rendered voice pack, `SUFLER_AUDIO_PACK`
  (default: the PDF path with `.sufler-audio.zip`). Expected counts are computed from the stored script
  (`scripts/e2e/oracle.py`), not hard-coded.
- **Artefacts:** `private/e2e/F<n>/<timestamp>/` (gitignored: screenshots show
  copyrighted text).

## Feature map

| feature | how to reach it | expected outcome |
|---|---|---|
| import a file | library -> "Importuj plik" -> pick PDF/DOCX/ODT/TXT | script screen opens; library tile `<file> · <n> kwestii`; IndexedDB `sufler/json` has `script/<sha256>` |
| import a Google Doc | library -> "Link do Google Docs" -> paste -> "Importuj link" | as above; unshared doc shows the "not shared" message (DOCS-contract.md) |
| delete a script | library -> tile trash "Usuń" -> confirm | tile gone, with its prefs, pack, recordings |
| pick roles | script -> "Twoje role" chips `<name> (<spoken lines>)`, "Piosenki" chips per song | chip selected; prefs `roles` saved |
| rehearse a section | script -> "Fragment" -> scene/song tile `kwestie a–b` | header `Przebieg 1 · kwestia 1/<cues>`; partner text shown and voiced (pack clip, else device TTS, else held silently for its reading time) |
| own line | rehearsal reaches a line of a picked role | "Twoja kwestia" + countdown; "Gotowe" or Space advances |
| custom / cumulative range | "Własny zakres…" / "Narastająco…" -> pick lines | rehearsal over that range |
| rehearsal settings | "Ustawienia próby": tempo, text visibility, self-grading, loop | applied to the next rehearsal |
| correct the text | "Narzędzia" -> "Popraw tekst" | speaker/kind/merge edits stored per script |
| timings and recordings | "Narzędzia" -> "Czasy i nagrania" | per-line pause override / own recording |
| Anki export | "Narzędzia" -> "Eksportuj talię Anki" (roles picked) | `<title>.apkg` download; one note per own spoken line, front = cue, back = own line |
| generate voices | "Narzędzia" -> "Generuj głosy" (shown when `/api/tts/health` is 200) | progress bar; `/api/tts/jobs/<id>` polled; pack stored when done |
| import a voice pack | "Narzędzia" -> "Importuj paczkę audio (.zip)" | "Głosy zapisane (<n> kwestii)" |

## Core flows (desktop)

| id | goal | command | last green |
|---|---|---|---|
| F1 | import the PDF through the real file picker; library lists it with its spoken-line count | `scripts/e2e_desktop.sh F1` | 2026-10-23 @ 4b38694 (864 lines, 825 spoken) |
| F2 | role picker: the role's chip shows all its spoken lines; every song (headed and unheaded ♪) has a chip | `scripts/e2e_desktop.sh F2` | 2026-10-23 @ 4b38694: Żagiewka (136) = 86 dialogue + 50 song lines; Piaskowy Wilk (39) = 18 + 21; 11 headed + 2 unheaded songs |
| F3 | the role + a scene where it speaks: partner text shown and audio started; a partner line ends by itself; the role's countdown runs; Space advances | `scripts/e2e_desktop.sh F3` | 2026-10-23 @ 4b38694: Żagiewka, 100 cues; without a pack device TTS fails (no voices) and the text is held; with the pack, two media clips play, the second ends by itself (3.23 s clip, `ended` 3.21 s after `playing`) |
| F4 | Anki export downloads an .apkg whose notes == the role's spoken lines, fronts carry the cue, backs the role's line | `scripts/e2e_desktop.sh F4` | 2026-10-23 @ 4b38694: Żagiewka 136 notes |
| F5 | with the voice service up, "Generuj głosy" gets a job and >= 1 progress answer through the wrapper (notes when the pack is stored: only a warm clip cache makes it in time) | `scripts/e2e_desktop.sh F5` | 2026-10-23 @ 4b38694: warm cache, "Głosy zapisane (825 kwestii)" 1.4 s after the first progress answer |
| F6 | "Importuj paczkę audio (.zip)" through the real file picker stores the pack; after a reload the role's scene plays its first partner line from it: an `HTMLMediaElement` clip (no device speech) whose duration equals that line's pack clip | `scripts/e2e_desktop.sh F6` | 2026-10-23 @ 4b38694: 825-clip pack; Żagiewka 2.71 s clip == pack, Wolf 3.09 s == pack |

On failure every flow prints `FAIL F<n> step <i>/<total>: <step> -> <why>;
shot: <path>` and exits 1.

Not covered: whether audio is audible (the probe sees `speechSynthesis.speak`
/ `HTMLMediaElement.play` calls, their outcome and clip duration, not sound), the Google
Docs import (needs a shared doc), and Android (built and checked separately).
