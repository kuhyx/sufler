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
  `F1` .. `F7` (one per call, each < 60 s, F2-F7 need F1's import; F1 needs
  the fresh profile `up` makes), `down`.
  After a wrapper-only rebuild: `scripts/e2e_desktop.sh wrapper`.
- **Role:** `E2E_ROLE` = character id kuhy plays, default `zagiewka`
  (Żagiewka); `E2E_ROLE=piaskowy-wilk` is kept green too.
- **Input:** a real play, `SUFLER_SCRIPT_PDF` (default `private/krasnale.pdf`,
  never committed), and for F6/F7 its rendered voice pack, `SUFLER_AUDIO_PACK`
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
| old parse, no kept document | open a script stored before `source/<id>` was kept | Android: re-parsed from the file_picker cache copy, summary once, `source/<id>` stored; no copy (or web): no message, "Narzędzia" -> "Odśwież parsowanie: wskaż plik" -> pick the same file -> summary, item gone; another file: "To inny plik niż ten skrypt" |
| delete a script | library -> tile trash "Usuń" -> confirm | tile gone, with its prefs, pack, recordings, source, backups |
| pick roles | hub -> "Moje role": chips `<name> (<spoken lines>)`, "Grupy" checkboxes, "Piosenki" cards (singers, verse count, first 3 lyrics, "Pokaż cały tekst") | prefs `roles` saved; ticking a character pre-ticks its groups ("twoja grupa"); unticking it keeps them (untick by hand) |
| learn | hub "Sceny" -> "Ucz się dalej: <section> · kwestia k" / "Zacznij naukę" / scene tile | rehearsal at the saved cue; partner text shown and voiced (pack clip, else device TTS, else held for its reading time) |
| own line (learn by heart) | rehearsal reaches a line of a picked role | "Twoja kwestia" + countdown, own text hidden ("Mów z pamięci…", "… słucham" when listening); "Gotowe"/Space/end of speech -> "Jak poszło?" with the text revealed -> "Dobrze"/"Źle" (✓/✗; Enter = suggested grade); "Źle" hides the text again, replays the line before it and asks again ("Jeszcze raz — aż będzie dobrze") until "Dobrze" (only the first attempt counts); listening on desktop also shows "Usłyszałem: „…”" + "Wygląda dobrze — Enter potwierdza ✓" / "Enter potwierdza ✗"; "Pauza x s" −/+ persists |
| only missed lines | hub "Sceny" -> "Tylko nieumiane (n)" | each line whose last first-attempt grade was ✗, with the line before it |
| pure run | rehearse a whole scene/song with every own line "Dobrze" on the first try | its tile in "Sceny"/"Piosenki" shows the "Czysty przebieg" badge (prefs `pureRuns`) |
| custom / cumulative range | "Sceny" -> "Własny zakres…" / "Narastająco…" -> pick lines | rehearsal over that range |
| record timings | one tap: scene/song tile mic "Nagraj czasy: <title>", or "Narzędzia" -> "Czasy i nagrania" -> "Nagraj czasy" | "Kwestia k/N", "Przeczytaj na głos:" + the line, level meter, "Słucham…"; each take ends on silence, is saved ("Zapisano kwestię n: x s (+1 s pauzy)") and the next line follows; on desktop the take is sent to `/api/tts/transcribe` and a transcript matching a later line asks "To brzmi jak kolejna kwestia (k/N)" -> "Tak, zapisz tam" / "Powtórz tę"; a take the mic did not hear ("Nie słyszę mikrofonu.") or the switch "Bez mikrofonu: stuknij po każdej kwestii" hides the line and shows a big "Skończyłem": the time from the line coming up to the tap is saved as its pause ("Zapisano kwestię n: pauza x s", manual, no recording, an existing recording kept) and the walk goes on; "Stop" -> "Gotowe: zapisano s z N" |
| rehearsal settings | tab "Ustawienia próby": tempo, Nauka / Bez tekstu / Czytanie, ✓/✗, listening, loop | applied to the next rehearsal |
| correct the text | tab "Narzędzia" -> "Popraw tekst" | speaker/kind/merge edits stored per script and logged in `edits/<id>` |
| timings and recordings | tab "Narzędzia" -> "Czasy i nagrania" | per-line pause override / own recording |
| Anki export | tab "Narzędzia" -> "Eksportuj talię Anki" (roles picked) | `<title>.apkg` download; one note per own spoken line, front = cue, back = own line |
| generate voices | tab "Narzędzia" -> "Generuj głosy" (shown when `/api/tts/health` is 200) | progress bar; `/api/tts/jobs/<id>` polled; pack stored when done |
| import a voice pack | tab "Narzędzia" -> "Importuj paczkę audio (.zip)" | "Głosy zapisane (<n> kwestii)"; a pack whose `fingerprint` differs from the parse: "Paczka głosów pochodzi z innej wersji tekstu — wygeneruj ponownie", not stored, never played |

## Core flows (desktop)

| id | goal | command | last green |
|---|---|---|---|
| F1 | import the PDF through the real file picker; library lists it with its spoken-line count | `scripts/e2e_desktop.sh F1` | 2026-10-23 @ fb2d1d0 (864 lines, 825 spoken; non-loopback requests: none) |
| F2 | a reload opens the last script's hub (not the library); "Moje role": the role's chip shows all its spoken lines; every song (headed and unheaded ♪) has a card under "Piosenki"; the cards show a "Śpiewa: …" preview | `scripts/e2e_desktop.sh F2` | 2026-10-23 @ fb2d1d0: Żagiewka (136) = 86 dialogue + 50 song lines; Piaskowy Wilk (39) = 18 + 21; 11 headed + 2 unheaded song cards |
| F3 | the role (with its pre-ticked groups) + a scene where it speaks: partner text shown and audio started; a partner line ends by itself; the role's countdown runs with its own text hidden ("Mów z pamięci…"); Space reveals the text under "Jak poszło?"; "Dobrze" advances | `scripts/e2e_desktop.sh F3` | 2026-10-23 @ fb2d1d0: Żagiewka, Scena 8, 100 cues, own line at kwestia 3; without a pack device TTS fails (no voices) and the text is held; with the pack two media clips play, the second ends by itself (3.23 s clip, `ended` 3.22 s after `playing`); Wolf (pack) Scena 3, kwestia 12/75 |
| F4 | Anki export downloads an .apkg whose notes == the spoken lines of the picked roles (the role + the groups its pick pre-ticks, re-derived from the data in `oracle.own_groups` and checked against prefs), fronts carry the cue, backs the own line | `scripts/e2e_desktop.sh F4` | 2026-10-23 @ fb2d1d0: Żagiewka 139 notes = 136 + 3 ("Wszyscy"; the 5-krasnale group adds none), Wolf 42 = 39 + 3 ("Wszyscy") |
| F5 | with the voice service up, "Generuj głosy" gets a job and >= 1 progress answer through the wrapper (notes when the pack is stored: only a warm clip cache makes it in time) | `scripts/e2e_desktop.sh F5` | 2026-10-23 @ fb2d1d0: warm cache, "Głosy zapisane (825 kwestii)" 1.5 s after the first progress answer |
| F6 | "Importuj paczkę audio (.zip)" through the real file picker stores the pack; after a reload the role's scene plays its first partner line from it: an `HTMLMediaElement` clip (no device speech) whose duration equals that line's pack clip | `scripts/e2e_desktop.sh F6` | 2026-10-23 @ fb2d1d0: 825-clip pack; Żagiewka 2.71 s clip == pack, Wolf 4.05 s == pack |
| F7 | speech recognition through the wrapper: `/api/tts/health` reports an `stt`; the first partner line's pack clip, as the mono 16 kHz PCM16 WAV the app's capture sends, POSTed like `TranscribeClient` (`/api/tts/transcribe?lang=pl`, `content-type: audio/wav`) returns 200 + a non-empty transcript similar (>= 0.6) to the stored line | `scripts/e2e_desktop.sh F7` | 2026-10-23 @ fb2d1d0: faster-whisper large-v3-turbo; Żagiewka line 686 (86 kB WAV) 200 in 0.2 s, similarity 1.00; Wolf line 318 (129 kB) 200 in 0.2 s, similarity 1.00 (warm recognizer) |

On failure every flow prints `FAIL F<n> step <i>/<total>: <step> -> <why>;
shot: <path>` and exits 1.

Not covered: the microphone itself (F7 posts a pack clip, not a live
take; the timing walk and listening need a real mic), whether audio is audible (the probe sees `speechSynthesis.speak`
/ `HTMLMediaElement.play` calls, their outcome and clip duration, not sound), the Google
Docs import (needs a shared doc), and Android (built and checked separately).
