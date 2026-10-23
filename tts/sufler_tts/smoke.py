"""GPU smoke test: the real engine child behind the HTTP API, end to end.

    python -m sufler_tts.smoke [PORT]     # default 8799; ~40 s incl. model load

Renders 5 synthetic Polish lines through POST /render exactly as the app
does, checks the pack, waits for the idle unload and confirms the engine
child left the GPU, then re-renders from cache. Exit 0 when all hold.
"""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

from sufler_tts.audio import read_opus_head
from sufler_tts.cache import ClipCache
from sufler_tts.engine import chatterbox_name
from sufler_tts.jobs import JobRunner
from sufler_tts.process_engine import ProcessEngine
from sufler_tts.server import make_server

LINES = (
    ("piaskowy-wilk", "Piaskowe Wilki nie jedzą krasnali, przysięgam na mój ogon!"),
    ("krolowa", "Królowa nie lubi czekać. Gdzie są moje lustra?"),
    ("blystek", "Hej, ho, do pracy czas, kopiemy złoto cały czas."),
    ("sniezynki", "Śnieżynki tańczą nad dachami, cicho, jak co roku."),
    ("", "A potem wszyscy wrócili do domu i zrobiło się cicho."),
)
NAMES = {"piaskowy-wilk": "Piaskowy Wilk", "krolowa": "Królowa"}
NAMES |= {"blystek": "Błystek", "sniezynki": "Śnieżynki"}
SCRIPT: dict[str, Any] = {
    "id": "smoke",
    "title": "Próba",
    "source": "synthetic",
    "characters": [{"id": k, "name": v} for k, v in NAMES.items()],
    "scenes": [],
    "songs": [],
    "lines": [
        {
            "index": i,
            "speakers": [s] if s else [],
            "text": t,
            "kind": "dialogue" if s else "song",
        }
        for i, (s, t) in enumerate(LINES)
    ],
}


def gpu_apps() -> str:
    """Compute processes on the GPU, per nvidia-smi."""
    query = ["--query-compute-apps=pid,used_memory", "--format=csv,noheader"]
    out = subprocess.run(
        ["nvidia-smi", *query], capture_output=True, text=True, check=False
    )
    return out.stdout.strip()


def _get(url: str) -> Any:
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read())


def _render(base: str) -> tuple[dict[str, Any], str]:
    body = json.dumps(SCRIPT).encode()
    req = urllib.request.Request(f"{base}/render", body, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        job_id = json.loads(r.read())["jobId"]
    seen = ""
    while (job := _get(f"{base}/jobs/{job_id}"))["state"] not in {"done", "error"}:
        seen = gpu_apps() or seen
        time.sleep(0.5)
    return job, seen


def main(port: int = 8799) -> int:
    """Run the smoke test; print evidence; 0 on success."""
    tmp = Path(tempfile.mkdtemp(prefix="sufler-smoke-"))
    factory = "sufler_tts.chatterbox_engine:ChatterboxEngine"
    engine = ProcessEngine(factory, chatterbox_name(), idle_s=4.0, watch_every=1.0)
    runner = JobRunner(engine, ClipCache(tmp / "cache"), tmp / "packs")
    server = make_server(runner, port=port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"
    try:
        print("health", _get(f"{base}/health"))
        start = time.monotonic()
        job, apps = _render(base)
        print(f"job {job} in {time.monotonic() - start:.1f}s; gpu during: {apps}")
        with urllib.request.urlopen(f"{base}/packs/smoke.zip", timeout=10) as r:
            pack = zipfile.ZipFile(io.BytesIO(r.read()))
        print("manifest", pack.read("manifest.json").decode())
        heads = {n: read_opus_head(pack.read(n)) for n in pack.namelist()[1:]}
        print("opus (channels, rate)", sorted(set(heads.values())), len(heads))
        idle_at = time.monotonic()
        while (left := gpu_apps()) and time.monotonic() - idle_at < 20:
            time.sleep(0.5)  # idle_s=4 + reaper tick + child teardown
        freed = time.monotonic() - idle_at
        print(f"GPU freed {freed:.1f}s after the job (idle 4s): apps={left!r}")
        start = time.monotonic()
        again, _ = _render(base)
        print(f"cached re-render {time.monotonic() - start:.2f}s {again}")
        ok = job["state"] == "done" and len(heads) == len(LINES) and not left
        return 0 if ok and set(heads.values()) == {(1, 24000)} else 1
    finally:
        server.shutdown()
        runner.stop()


if __name__ == "__main__":
    sys.exit(main(*(int(a) for a in sys.argv[1:2])))
