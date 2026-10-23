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
| open the last script | start the app with a script imported | that script's hub opens at once (the only script, if none remembered); back = library |
| import a file | library -> "Importuj plik" (empty library) or "+" "Importuj" -> pick PDF/DOCX/ODT/TXT | script opens; first visit shows "Moje role" once; library tile `<file> · <n> kwestii`; IndexedDB `sufler/json` has `script/<sha256>`, `sufler/bytes` has `source/<sha256>` |
| import a Google Doc | library -> "Link do Google Docs" -> paste -> "Importuj link" | as above; unshared doc shows the "not shared" message (DOCS-contract.md) |
| re-import / newer parser | import the same file again, or open a script whose `meta/<id>` parserVersion is older | "Zaktualizowano parsowanie: <n> … przeniesione, <m> utraconych"; timings, recordings, grades, resume move to the new line indices |
| delete a script | library -> tile trash "Usuń" -> confirm | tile gone, with its prefs, pack, recordings, source, backups |
| pick roles | hub -> "Moje role": chips `<name> (<spoken lines>)`, "Grupy" checkboxes, "Piosenki" cards (singers, verse count, first 3 lyrics, "Pokaż cały tekst") | prefs `roles` saved; ticking a character pre-ticks its groups |
| learn | hub "Sceny" -> "Ucz się dalej: <section> · kwestia k" / "Zacznij naukę" / scene tile | rehearsal at the saved cue; partner text shown and voiced (pack clip, else device TTS, else held for its reading time) |
| own line | rehearsal reaches a line of a picked role | "Twoja kwestia" + countdown, text hidden ("Mów z pamięci…"); "Gotowe"/Space/silence (listening) -> text revealed -> "Dobrze"/"Źle" (Enter = suggested grade); "Pauza x s" −/+ persists |
| only missed lines | hub "Sceny" -> "Tylko nieumiane (n)" | each ✗ line with the line before it |
| custom / cumulative range | "Sceny" -> "Własny zakres…" / "Narastająco…" -> pick lines | rehearsal over that range |
| record timings | scene/song tile mic "Nagraj czasy: <title>", or "Narzędzia" -> "Czasy i nagrania" -> "Nagraj czasy" | "Kwestia k/N", level meter; each line ends on silence, saved, next; skipped line prompt; "Stop" |
| rehearsal settings | tab "Ustawienia próby": tempo, Nauka / Bez tekstu / Czytanie, ✓/✗, listening, loop | applied to the next rehearsal |
| correct the text | tab "Narzędzia" -> "Popraw tekst" | speaker/kind/merge edits stored per script and logged in `edits/<id>` |
| timings and recordings | tab "Narzędzia" -> "Czasy i nagrania" | per-line pause override / own recording |
| Anki export | tab "Narzędzia" -> "Eksportuj talię Anki" (roles picked) | `<title>.apkg` download; one note per own spoken line, front = cue, back = own line |
| generate voices | tab "Narzędzia" -> "Generuj głosy" (shown when `/api/tts/health` is 200) | progress bar; `/api/tts/jobs/<id>` polled; pack stored when done |
| import a voice pack | tab "Narzędzia" -> "Importuj paczkę audio (.zip)" | "Głosy zapisane (<n> kwestii)"; a pack whose `fingerprint` differs from the parse: "Paczka głosów pochodzi z innej wersji tekstu — wygeneruj ponownie", not stored, never played |

## Core flows (desktop)

| id | goal | command | last green |
|---|---|---|---|
| F1 | import the PDF through the real file picker; library lists it with its spoken-line count | `scripts/e2e_desktop.sh F1` | 2026-10-23 @ 4b38694 + font fix (864 lines, 825 spoken; non-loopback requests: none) |
| F2 | role picker: the role's chip shows all its spoken lines; every song (headed and unheaded ♪) has a chip | `scripts/e2e_desktop.sh F2` | 2026-10-23 @ 4b38694: Żagiewka (136) = 86 dialogue + 50 song lines; Piaskowy Wilk (39) = 18 + 21 (dialogue blocks per krasnale_test); 11 headed + 2 unheaded songs |
| F3 | the role + a scene where it speaks: partner text shown and audio started; a partner line ends by itself; the role's countdown runs; Space advances | `scripts/e2e_desktop.sh F3` | 2026-10-23 @ 4b38694: Żagiewka, 100 cues; without a pack device TTS fails (no voices) and the text is held; with the pack, two media clips play, the second ends by itself (3.23 s clip, `ended` 3.21 s after `playing`); Wolf (pack) at kwestia 159/242 |
| F4 | Anki export downloads an .apkg whose notes == the role's spoken lines, fronts carry the cue, backs the role's line | `scripts/e2e_desktop.sh F4` | 2026-10-23 @ 4b38694: Żagiewka 136 notes, Wolf 39 |
| F5 | with the voice service up, "Generuj głosy" gets a job and >= 1 progress answer through the wrapper (notes when the pack is stored: only a warm clip cache makes it in time) | `scripts/e2e_desktop.sh F5` | 2026-10-23 @ 4b38694: warm cache, "Głosy zapisane (825 kwestii)" 1.4 s after the first progress answer |
| F6 | "Importuj paczkę audio (.zip)" through the real file picker stores the pack; after a reload the role's scene plays its first partner line from it: an `HTMLMediaElement` clip (no device speech) whose duration equals that line's pack clip | `scripts/e2e_desktop.sh F6` | 2026-10-23 @ 4b38694: 825-clip pack; Żagiewka 2.71 s clip == pack, Wolf 3.09 s == pack |

After the 2026-10-23 UX rework (hub tabs, "Moje role" screen, learning
flow) the flows' navigation was updated but F1–F6 were NOT re-run: the
"last green" column predates it. F4's expected note count does not yet add
the group lines a pre-ticked group (e.g. "Wszyscy") contributes.

On failure every flow prints `FAIL F<n> step <i>/<total>: <step> -> <why>;
shot: <path>` and exits 1.

Not covered: whether audio is audible (the probe sees `speechSynthesis.speak`
/ `HTMLMediaElement.play` calls, their outcome and clip duration, not sound), the Google
Docs import (needs a shared doc), and Android (built and checked separately).
