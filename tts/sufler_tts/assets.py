"""Where on-disk assets live: synthetic voice prompts, samples, model weights.

Nothing here is committed; `scripts/install_tts.sh` fills these via
`python -m sufler_tts.fetch_assets`.
"""

from __future__ import annotations

import hashlib
import os
from functools import cache
from pathlib import Path

DATA = Path(os.environ.get("SUFLER_DATA", Path.home() / ".local/share/sufler"))
PROMPTS = DATA / "voice-prompts"
SAMPLES = DATA / "voice-samples"
CHECKS = DATA / "voice-check"
PIPER_MODELS = DATA / "piper"
PIPER_PREFIX = "piper-"


def prompt_path(base: str) -> Path | None:
    """The synthetic prompt WAV for a `piper-<name>` base; None for `default`."""
    if not base.startswith(PIPER_PREFIX):
        return None
    return PROMPTS / f"{base.removeprefix(PIPER_PREFIX)}.wav"


@cache
def _digest(path: Path, mtime_ns: int) -> str:
    del mtime_ns  # part of the memo key only: a regenerated prompt re-hashes
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prompt_digest(base: str) -> str:
    """sha256 of the prompt WAV (empty when there is none), for cache keys."""
    path = prompt_path(base)
    if path is None or not path.is_file():
        return ""
    return _digest(path, path.stat().st_mtime_ns)
