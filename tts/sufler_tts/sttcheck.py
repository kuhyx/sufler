"""Real-GPU check of POST /transcribe against the live service (not in CI).

    python -m sufler_tts.sttcheck render   # TTS 3 Polish sentences via /render
    python -m sufler_tts.sttcheck wer      # transcribe them: WER, latency, VRAM

`render` resumes the job it started if the model was still loading when its
50 s budget ran out. Needs the service on 127.0.0.1:8791.
"""

from __future__ import annotations

import io
import json
import re
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

from sufler_tts.assets import DATA
from sufler_tts.server import PORT

BASE = f"http://127.0.0.1:{PORT}"
WORK = DATA / "stt-check"
SENTENCES = [
    "Piaskowe Wilki nie jedzą Krasnali, bo Krasnale są za chude i za głośne.",
    "Wczoraj wieczorem poszliśmy nad rzekę, żeby zobaczyć, jak zachodzi słońce.",
    "Proszę otworzyć okno, ponieważ w tym pokoju jest bardzo duszno.",
]
WARM_RUNS = 3


def _script() -> dict[str, object]:
    lines = [
        {"index": i, "speakers": ["a"], "text": t, "kind": "dialogue"}
        for i, t in enumerate(SENTENCES)
    ]
    return {
        "id": "sttcheck",
        "title": "STT check",
        "source": "synthetic",
        "characters": [{"id": "a", "name": "A", "aliases": []}],
        "scenes": [],
        "songs": [],
        "lines": lines,
    }


def _call(path: str, data: bytes | None = None) -> bytes:
    with urllib.request.urlopen(BASE + path, data, timeout=55) as r:
        body: bytes = r.read()
    return body


def render() -> None:
    """Submit (or resume) the render job and unpack the clips into WORK."""
    WORK.mkdir(parents=True, exist_ok=True)
    state = WORK / "job"
    if not state.is_file():
        body = json.dumps(_script()).encode()
        state.write_text(json.loads(_call("/render", body))["jobId"])
    job = state.read_text()
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        info = json.loads(_call(f"/jobs/{job}"))
        if info["state"] == "error":
            state.unlink()
            sys.exit(f"render failed: {info}")
        if info["state"] == "done":
            break
        time.sleep(1)
    else:
        sys.exit("still rendering; run `render` again")
    state.unlink()
    zf = zipfile.ZipFile(io.BytesIO(_call("/packs/sttcheck.zip")))
    for name in zf.namelist():
        if name.startswith("audio/"):
            (WORK / Path(name).name).write_bytes(zf.read(name))
    print(f"clips in {WORK}")


def words(text: str) -> list[str]:
    """Lower-case words with punctuation dropped (Polish letters kept)."""
    return re.findall(r"\w+", text.lower())


def wer(reference: str, hypothesis: str) -> float:
    """Word error rate: word-level edit distance / reference length."""
    ref, hyp = words(reference), words(hypothesis)
    prev = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        cur = [i]
        for j, h in enumerate(hyp, 1):
            cost = 0 if r == h else 1
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
        prev = cur
    return prev[-1] / len(ref)


def vram_mib() -> int:
    """Total GPU memory in use (MiB) per nvidia-smi."""
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    return int(out.stdout.split()[0])


def check() -> None:
    """Transcribe each clip: WER, speech bounds, warm latency, VRAM."""
    peak = vram_mib()
    print(f"VRAM before: {peak} MiB")
    for i, sentence in enumerate(SENTENCES):
        clip = (WORK / f"{i}.ogg").read_bytes()
        _call("/transcribe?lang=pl", clip)  # warm-up (loads the model)
        times = []
        for _ in range(WARM_RUNS):
            t0 = time.monotonic()
            result = json.loads(_call("/transcribe?lang=pl", clip))
            times.append(time.monotonic() - t0)
            peak = max(peak, vram_mib())
        print(
            f"[{i}] WER {wer(sentence, result['text']):.2f}  "
            f"warm {min(times):.2f}-{max(times):.2f}s  "
            f"speech {result['speechStart']}-{result['speechEnd']}s\n"
            f"    ref: {sentence}\n    hyp: {result['text']}"
        )
    print(f"VRAM peak (Chatterbox + Whisper loaded): {peak} MiB")


def main() -> None:
    """CLI entry point."""
    if len(sys.argv) != 2 or sys.argv[1] not in {"render", "wer"}:
        sys.exit(__doc__)
    render() if sys.argv[1] == "render" else check()


if __name__ == "__main__":
    main()
