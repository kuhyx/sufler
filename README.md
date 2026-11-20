# sufler

Learn your lines. Drop in a play (PDF, DOCX, ODT, TXT or a Google Docs link),
pick who you play, pick a scene or song, and rehearse: every other character's
line is read aloud in Polish, then the app waits long enough for you to say
yours. Export the same cue → line pairs as an Anki deck.

Runs on Android and on the desktop (web build in a Chrome app window).
Character voices are generated on the PC CPU with Chatterbox Multilingual
(MIT); the phone falls back to the system Polish voice. Speech recognition
(timing your lines) runs on the PC GPU with whisper.cpp through Vulkan (MIT,
Arch `whisper-cpp` + `ggml-vulkan`, no CUDA libraries).

Data contract: [DOCS-contract.md](DOCS-contract.md).
