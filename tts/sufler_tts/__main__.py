"""`python -m sufler_tts`: the voice service on 127.0.0.1:8791 (systemd unit)."""

from __future__ import annotations

import signal
import sys
from types import FrameType

from sufler_tts.assets import DATA
from sufler_tts.cache import ClipCache
from sufler_tts.engine import chatterbox_name
from sufler_tts.jobs import JobRunner
from sufler_tts.process_engine import ProcessEngine
from sufler_tts.server import PORT, make_server

ENGINE_FACTORY = "sufler_tts.chatterbox_engine:ChatterboxEngine"


def _exit(signum: int, frame: FrameType | None) -> None:
    del frame
    sys.exit(128 + signum)


def main() -> None:
    """Serve until SIGTERM; the engine child is stopped on the way out."""
    engine = ProcessEngine(ENGINE_FACTORY, chatterbox_name())
    runner = JobRunner(engine, ClipCache(), DATA / "packs")
    server = make_server(runner)
    signal.signal(signal.SIGTERM, _exit)
    print(f"sufler-tts on http://127.0.0.1:{PORT} ({engine.name})", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        engine.close()


if __name__ == "__main__":
    main()
