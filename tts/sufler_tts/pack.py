"""The audio pack zip, exactly as DOCS-contract.md "Audio pack" specifies."""

from __future__ import annotations

import json
import os
import zipfile
from pathlib import Path


def pack_name(script_id: str) -> str:
    """`<script-id>.sufler-audio.zip`."""
    return f"{script_id}.sufler-audio.zip"


def build_pack(
    script_id: str,
    engine: str,
    voices: dict[str, str],
    clips: dict[int, Path],
    packs: Path,
) -> Path:
    """Write manifest.json + audio/<index>.ogg into the pack, atomically."""
    manifest = {
        "scriptId": script_id,
        "engine": engine,
        "voices": voices,
        "lines": {str(i): f"audio/{i}.ogg" for i in sorted(clips)},
    }
    packs.mkdir(parents=True, exist_ok=True)
    out = packs / pack_name(script_id)
    tmp = out.with_suffix(f".{os.getpid()}.tmp")
    # Opus is already compressed: store, don't deflate.
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_STORED) as z:
        z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        for index in sorted(clips):
            z.write(clips[index], f"audio/{index}.ogg")
    tmp.replace(out)
    return out
