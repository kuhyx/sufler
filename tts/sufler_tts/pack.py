"""The audio pack zip, exactly as DOCS-contract.md "Audio pack" specifies."""

from __future__ import annotations

import hashlib
import json
import os
import zipfile
from pathlib import Path

from sufler_tts.script import Script


def pack_name(script_id: str) -> str:
    """`<script-id>.sufler-audio.zip`."""
    return f"{script_id}.sufler-audio.zip"


def script_fingerprint(script: Script) -> str:
    r"""sha256 hex of every line as `index\tkind\tspeakers,joined\ttext\n` (UTF-8).

    The app recomputes it from its own parse and rejects a pack that differs.
    """
    digest = hashlib.sha256()
    for line in script.lines:
        row = f"{line.index}\t{line.kind}\t{','.join(line.speakers)}\t{line.text}\n"
        digest.update(row.encode())
    return digest.hexdigest()


def build_pack(
    script_id: str,
    engine: str,
    voices: dict[str, str],
    clips: dict[int, Path],
    packs: Path,
    fingerprint: str,
) -> Path:
    """Write manifest.json + audio/<index>.ogg into the pack, atomically."""
    manifest = {
        "scriptId": script_id,
        "engine": engine,
        "voices": voices,
        "fingerprint": fingerprint,
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
