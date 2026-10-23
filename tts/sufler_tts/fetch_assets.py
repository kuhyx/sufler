"""Fetch model weights and build the synthetic voice prompts (idempotent).

    python -m sufler_tts.fetch_assets weights [FILE ...]
    python -m sufler_tts.fetch_assets piper [VOICE ...]
    python -m sufler_tts.fetch_assets prompts

Prompts are Piper TTS output (synthetic), never a human recording: Chatterbox
takes its timbre from them for the voices whose base is `piper-<name>`.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import urllib.request
from pathlib import Path

from sufler_tts.assets import PIPER_MODELS, PIPER_PREFIX, PROMPTS, prompt_path
from sufler_tts.voices import BANK

REPO_ID = "ResembleAI/chatterbox"
WEIGHTS = (
    "ve.pt",
    "t3_mtl23ls_v2.safetensors",
    "s3gen.pt",
    "grapheme_mtl_merged_expanded_v1.json",
    "conds.pt",
    "Cangjie5_TC.json",
)
PIPER_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL"
PIPER_QUALITY = {"darkman": "medium", "gosia": "medium", "mc_speech": "medium"}
PROMPT_TEXT = (
    "Dzień dobry. Czytam kwestie innych postaci, żeby aktor mógł spokojnie "
    "ćwiczyć swoją rolę. Mówię wyraźnie, w naturalnym tempie, "
    "a potem robię krótką pauzę."
)


def fetch_weights(files: list[str]) -> None:
    """Download Chatterbox Multilingual files into the Hugging Face cache."""
    from huggingface_hub import hf_hub_download  # noqa: PLC0415 - heavy import

    for name in files or WEIGHTS:
        print(hf_hub_download(REPO_ID, name))


def _piper_files(voice: str) -> list[tuple[str, Path]]:
    stem = f"pl_PL-{voice}-{PIPER_QUALITY[voice]}"
    url = f"{PIPER_URL}/{voice}/{PIPER_QUALITY[voice]}/{stem}"
    return [
        (f"{url}{ext}", PIPER_MODELS / f"{stem}{ext}")
        for ext in (".onnx", ".onnx.json")
    ]


def fetch_piper(voices: list[str]) -> None:
    """Download Polish Piper voices (skips files already present)."""
    PIPER_MODELS.mkdir(parents=True, exist_ok=True)
    for voice in voices or sorted(PIPER_QUALITY):
        for url, dest in _piper_files(voice):
            if dest.is_file():
                continue
            tmp = dest.with_suffix(dest.suffix + ".part")
            with urllib.request.urlopen(url, timeout=50) as r, tmp.open("wb") as f:
                shutil.copyfileobj(r, f)
            tmp.replace(dest)
            print(dest)


def build_prompts() -> None:
    """Render one synthetic prompt WAV per `piper-*` base used by the bank."""
    piper = shutil.which("piper") or str(Path.home() / ".local/bin/piper")
    PROMPTS.mkdir(parents=True, exist_ok=True)
    for base in sorted({v.base for v in BANK if v.base.startswith(PIPER_PREFIX)}):
        out = prompt_path(base)
        if out is None or out.is_file():
            continue
        model = _piper_files(base.removeprefix(PIPER_PREFIX))[0][1]
        tmp = out.with_suffix(".part.wav")
        cmd = [piper, "-m", str(model), "-f", str(tmp)]
        subprocess.run(cmd, input=PROMPT_TEXT, text=True, check=True)
        tmp.replace(out)
        print(out)


def main(argv: list[str] | None = None) -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("what", choices=["weights", "piper", "prompts"])
    parser.add_argument("names", nargs="*")
    args = parser.parse_args(argv)
    if args.what == "weights":
        fetch_weights(args.names)
    elif args.what == "piper":
        fetch_piper(args.names)
    else:
        build_prompts()


if __name__ == "__main__":
    main()
