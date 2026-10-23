## Commands

- run: `flutter run`
- test: `flutter test --reporter=compact`
- test-changed: `scripts/test_changed.sh`
- lint: `flutter analyze`
- coverage: `flutter test --reporter=compact --coverage`
- coverage-gaps: `coverage-gaps coverage/lcov.info`

## Project rules

- Never commit a real script (PDF/DOCX/ODT) or text extracted from one: plays are
  copyrighted and this repo is public. Integration tests read a local path from
  `SUFLER_SCRIPT_PDF`; in-repo fixtures are synthetic.
- `lib/model/` + `DOCS-contract.md` are the contract between importers,
  rehearsal, TTS and Anki export. Change both together.
- Desktop = web build in Chrome via a loopback wrapper (see the
  `flutter-desktop-to-chrome` skill); there is deliberately no `linux/` target.
