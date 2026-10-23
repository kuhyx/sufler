"""Content-addressed clip cache: re-renders after an edit redo only changed lines."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
from pathlib import Path

from sufler_tts.assets import prompt_digest
from sufler_tts.textprep import TEXTPREP_VERSION
from sufler_tts.voices import Voice

DEFAULT_ROOT = Path.home() / ".local/share/sufler/tts-cache"


def clip_key(text: str, voice: Voice, engine: str) -> str:
    """sha256 over the text, the full voice spec, the engine and the prep version."""
    payload = {
        "text": text,
        "voice": voice.spec(),
        "prompt": prompt_digest(voice.base),
        "engine": engine,
        "prep": TEXTPREP_VERSION,
    }
    blob = json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()
    return hashlib.sha256(blob).hexdigest()


def seed_for(key: str) -> int:
    """A per-clip seed, so a re-render of the same clip sounds the same."""
    return int(key[:8], 16)


class ClipCache:
    """`<root>/<k[:2]>/<k>.ogg`, written atomically."""

    def __init__(self, root: Path = DEFAULT_ROOT) -> None:
        """Use `root` (created on first write)."""
        self.root = root

    def path(self, key: str) -> Path:
        """Where the clip for `key` lives (whether or not it exists)."""
        return self.root / key[:2] / f"{key}.ogg"

    def get(self, key: str) -> Path | None:
        """The cached clip, or None on a miss."""
        path = self.path(key)
        return path if path.is_file() else None

    def put(self, key: str, src: Path) -> Path:
        """Move `src` into the cache under `key`."""
        path = self.path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        shutil.move(src, tmp)
        tmp.replace(path)
        return path
