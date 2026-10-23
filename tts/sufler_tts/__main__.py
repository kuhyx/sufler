"""`python -m sufler_tts`: the voice service on 127.0.0.1:8791 (systemd unit)."""

from __future__ import annotations

import logging
import os
import signal
import sys
from types import FrameType

from sufler_tts.assets import DATA
from sufler_tts.assist import Assist
from sufler_tts.cache import ClipCache
from sufler_tts.engine import chatterbox_name
from sufler_tts.explain import ClaudeExplainer
from sufler_tts.jobs import JobRunner
from sufler_tts.process_engine import ProcessEngine
from sufler_tts.process_stt import ProcessTranscriber
from sufler_tts.relay import setup as relay_setup
from sufler_tts.server import PORT, make_server
from sufler_tts.transcribe import whisper_name

ENGINE_FACTORY = "sufler_tts.chatterbox_engine:ChatterboxEngine"
STT_FACTORY = "sufler_tts.whisper_engine:WhisperTranscriber"


def _exit(signum: int, frame: FrameType | None) -> None:
    del frame
    sys.exit(128 + signum)


def main() -> None:
    """Serve until SIGTERM; the engine child is stopped on the way out.

    The phone relay (RTDB) runs in the same process, on the same engine,
    unless `SUFLER_RELAY=0` or no session is seeded (then: HTTP only).
    """
    logging.basicConfig(format="%(name)s: %(message)s")
    engine = ProcessEngine(ENGINE_FACTORY, chatterbox_name())
    runner = JobRunner(engine, ClipCache(), DATA / "packs")
    stt = ProcessTranscriber(STT_FACTORY, whisper_name())
    assist = Assist(engine, runner.cache, runner.packs, ClaudeExplainer())
    server = make_server(runner, transcriber=stt, assist=assist)
    signal.signal(signal.SIGTERM, _exit)
    print(f"sufler-tts on http://127.0.0.1:{PORT} ({engine.name})", flush=True)
    relay = relay_setup.start(assist, os.environ)
    if relay is not None:
        print(f"relay on: phone requests as {relay.relay.device}", flush=True)
    try:
        server.serve_forever()
    finally:
        if relay is not None:
            relay.stop()
        server.server_close()
        engine.close()
        stt.close()


if __name__ == "__main__":
    main()
