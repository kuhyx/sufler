"""Fetch model weights and build the synthetic voice prompts (idempotent).

    python -m sufler_tts.fetch_assets weights [FILE ...]
    python -m sufler_tts.fetch_assets whisper [FILE ...]
    python -m sufler_tts.fetch_assets piper [VOICE ...]
    python -m sufler_tts.fetch_assets prompts

Downloads are plain stdlib HTTP from revision-pinned Hugging Face URLs, each
verified against a pinned sha256 (see `sufler_tts.download`).

Prompts are Piper TTS output (synthetic), never a human recording: Chatterbox
takes its timbre from them for the voices whose base is `piper-<name>`.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from sufler_tts import download
from sufler_tts.assets import (
    CHATTERBOX_REPO,
    CHATTERBOX_REVISION,
    PIPER_MODELS,
    PIPER_PREFIX,
    PROMPTS,
    WHISPER_DIR,
    WHISPER_REPO,
    WHISPER_REVISION,
    prompt_path,
)
from sufler_tts.assets import WEIGHTS as WEIGHTS_DIR
from sufler_tts.voices import BANK

HF = "https://huggingface.co"
# name -> sha256 at CHATTERBOX_REVISION (the LFS oid, or the hash of the blob).
WEIGHTS = {
    "ve.pt": "4b16d836bc598509860f6fa068165a8bb5e9ac84f05582dfcf278a5a372879f1",
    "t3_mtl23ls_v2.safetensors": (
        "b1237586127ce98e7800a68e49938eb5092846862aabcb6e17b2fda7889a6c75"
    ),
    "s3gen.pt": "9b9ff07e60b20c136e2b1b3d7563a24604e8d2c4c267888d1ee929dd0151d2a3",
    "grapheme_mtl_merged_expanded_v1.json": (
        "69632f47220a788a52ce2661d096453c5655e9bf25289d89a8d832c46ee07dbf"
    ),
    "conds.pt": "6552d70568833628ba019c6b03459e77fe71ca197d5c560cef9411bee9d87f4e",
    "Cangjie5_TC.json": (
        "7073fd9de919443ae88e0bd2449917a65fe54898a4413ed1edcc4b67f28bce8c"
    ),
}
# faster-whisper large-v3-turbo files at WHISPER_REVISION (sha256 of the bytes).
WHISPER = {
    "model.bin": "e76620f83d5f5b69efd3d87e3dc180c1bd21df9fbebacfd4335e5e1efcc018da",
    "config.json": "b0253ea6c0d3bea6b1e19e91a02acfd3b53f4467362efcb5a3e6b16c9b3a9b7e",
    "preprocessor_config.json": (
        "7ccc62c6f2765af1f3b46c00c9b5894426835a05021c8b9c01eecb6dfb542711"
    ),
    "tokenizer.json": (
        "297b13372ac43916285644fb9687add3cc62ee2a1adb60da3dc25cc94c1871fd"
    ),
    "vocabulary.json": (
        "c69260f2ab26d659b7c398f9a2b2b48ed0df16c3b47d7326782fd9cba71690c1"
    ),
}
PIPER_REVISION = "5041a7a49ae5b3a0f30e6837769eb03fdbb231bd"
PIPER_URL = f"{HF}/rhasspy/piper-voices/resolve/{PIPER_REVISION}/pl/pl_PL"
PIPER_QUALITY = {"darkman": "medium", "gosia": "medium", "mc_speech": "medium"}
# (voice, extension) -> sha256 at PIPER_REVISION.
PIPER_SHA256 = {
    ("darkman", ".onnx"): (
        "db505438a5364e8e2e0242c4324130a873ed660dfbe8d9689cef428ffb1b645f"
    ),
    ("darkman", ".onnx.json"): (
        "70f999f11fa8ad13d3ef779041ee93c9f38be5abdbacdfad42449712fe91c81b"
    ),
    ("gosia", ".onnx"): (
        "38f66464240ed74f186e6b7dc13c6e3b22e023426299f25c2b3cc9dfa9373fbc"
    ),
    ("gosia", ".onnx.json"): (
        "1aefb31a9d53ffe44a8163ff73ec833acb7a6253848f6bb0403d8a66f9c7510d"
    ),
    ("mc_speech", ".onnx"): (
        "a6b043358bc81e6c111a5140606a21959ce7f34969b8b7207f62869787cc3907"
    ),
    ("mc_speech", ".onnx.json"): (
        "b8bb11228e15c505219846a88fdc129e93f57e774ed7f9bac263156d1aa3d324"
    ),
}
PROMPT_TEXT = (
    "Dzień dobry. Czytam kwestie innych postaci, żeby aktor mógł spokojnie "
    "ćwiczyć swoją rolę. Mówię wyraźnie, w naturalnym tempie, "
    "a potem robię krótką pauzę."
)


def fetch_weights(files: list[str]) -> None:
    """Download Chatterbox Multilingual weights into `assets.WEIGHTS`."""
    base = f"{HF}/{CHATTERBOX_REPO}/resolve/{CHATTERBOX_REVISION}"
    for name in files or list(WEIGHTS):
        dest = WEIGHTS_DIR / name
        if download.fetch(f"{base}/{name}", dest, WEIGHTS[name]):
            print(dest)


def fetch_whisper(files: list[str]) -> None:
    """Download the Whisper large-v3-turbo CT2 model into `assets.WHISPER_DIR`."""
    base = f"{HF}/{WHISPER_REPO}/resolve/{WHISPER_REVISION}"
    for name in files or list(WHISPER):
        dest = WHISPER_DIR / name
        if download.fetch(f"{base}/{name}", dest, WHISPER[name]):
            print(dest)


def _piper_files(voice: str) -> list[tuple[str, Path, str]]:
    stem = f"pl_PL-{voice}-{PIPER_QUALITY[voice]}"
    url = f"{PIPER_URL}/{voice}/{PIPER_QUALITY[voice]}/{stem}"
    return [
        (f"{url}{ext}", PIPER_MODELS / f"{stem}{ext}", PIPER_SHA256[voice, ext])
        for ext in (".onnx", ".onnx.json")
    ]


def fetch_piper(voices: list[str]) -> None:
    """Download Polish Piper voices (verified files are skipped)."""
    for voice in voices or sorted(PIPER_QUALITY):
        for url, dest, sha256 in _piper_files(voice):
            if download.fetch(url, dest, sha256):
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
    parser.add_argument("what", choices=["weights", "whisper", "piper", "prompts"])
    parser.add_argument("names", nargs="*")
    args = parser.parse_args(argv)
    sets = {"weights": WEIGHTS, "whisper": WHISPER, "piper": PIPER_QUALITY}
    known = sets.get(args.what, {})
    if unknown := [n for n in args.names if n not in known]:
        parser.error(f"unknown {args.what}: {', '.join(unknown)}")
    if args.what == "weights":
        fetch_weights(args.names)
    elif args.what == "whisper":
        fetch_whisper(args.names)
    elif args.what == "piper":
        fetch_piper(args.names)
    else:
        build_prompts()


if __name__ == "__main__":
    main()
