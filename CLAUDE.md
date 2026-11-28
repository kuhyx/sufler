## Commands

- run: `flutter run`
- test: `flutter test -j 4 --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: n/a: dropped (kuhy, 2026-11-27)
- coverage: n/a: dropped (kuhy, 2026-11-27)
- coverage-gaps: n/a: dropped (kuhy, 2026-11-27)
- build-apk: `scripts/build_apk.sh prep`, then `dart`, `kotlin`, `assemble` (one call each)
- deploy: `scripts/deploy.sh`

`-j 4`: each widget-test process (test/ui) peaks ~300 MB; default -j (=cores)
exceeds the 2 GiB `capped.sh` ceiling and a flutter_tester is OOM-killed
("Cannot add event while adding stream"). CI is uncapped and keeps the default.

`deploy` pulls ~/src/sufler (the TTS unit runs from it), installs the desktop
package, restarts `sufler-tts` and installs the release APK on the Pixel
(`install -r` only); `--health` runs just the checks.

Never run a one-shot `flutter build apk --release`: it holds a build slot
~73 s (over the 60 s cap). `scripts/build_apk.sh` and `deploy` build in
warm-daemon stages, each under 60 s.

## Project rules

- Never commit a real script (PDF/DOCX/ODT) or text extracted from one: plays are
  copyrighted and this repo is public. Integration tests read a local path from
  `SUFLER_SCRIPT_PDF`; in-repo fixtures are synthetic.
- `lib/model/` + `DOCS-contract*.md` are the contract between importers,
  rehearsal, TTS and Anki export. Change both together.
- `lib/assist/firebase_local.dart` is generated and gitignored: run
  `dart run tool/write_firebase_config.dart` once per checkout (`--placeholder`
  without `~/.config/crdt-sync/`), or nothing compiles. Never commit it.
- Desktop = web build in Chrome via a loopback wrapper (see the
  `flutter-desktop-to-chrome` skill); there is deliberately no `linux/` target.
