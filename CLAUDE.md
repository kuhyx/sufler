## Commands

- run: `flutter run`
- test: `flutter test -j 4 --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: `flutter analyze`
- coverage: `flutter test -j 4 --reporter=compact --coverage`
- coverage-gaps: `coverage-gaps coverage/lcov.info`

`-j 4`: each widget-test process (test/ui) peaks ~300 MB; default -j (=cores)
exceeds the 2 GiB `capped.sh` ceiling and a flutter_tester is OOM-killed
("Cannot add event while adding stream"). CI is uncapped and keeps the default.

## Project rules

- Never commit a real script (PDF/DOCX/ODT) or text extracted from one: plays are
  copyrighted and this repo is public. Integration tests read a local path from
  `SUFLER_SCRIPT_PDF`; in-repo fixtures are synthetic.
- `lib/model/` + `DOCS-contract.md` are the contract between importers,
  rehearsal, TTS and Anki export. Change both together.
- `lib/assist/firebase_local.dart` is generated and gitignored: run
  `dart run tool/write_firebase_config.dart` once per checkout (`--placeholder`
  without `~/.config/crdt-sync/`), or nothing compiles. Never commit it.
- Desktop = web build in Chrome via a loopback wrapper (see the
  `flutter-desktop-to-chrome` skill); there is deliberately no `linux/` target.
