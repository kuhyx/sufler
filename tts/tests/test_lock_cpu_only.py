"""uv.lock pulls no proprietary NVIDIA/CUDA wheel: torch runs on the CPU build.

The FOSS audit flags every `nvidia-*` / `cuda-*` wheel. torch and torchaudio
must come from PyTorch's CPU index (`+cpu` builds), because their PyPI wheels
depend on, or link against, the CUDA runtime.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

LOCK = Path(__file__).resolve().parent.parent / "uv.lock"
CPU_INDEX = "https://download.pytorch.org/whl/cpu"
CUDA_PREFIXES = ("nvidia-", "cuda-")


def _packages() -> list[dict[str, object]]:
    with LOCK.open("rb") as fh:
        packages: list[dict[str, object]] = tomllib.load(fh)["package"]
    return packages


def test_lock_has_no_nvidia_or_cuda_package() -> None:
    names = [str(p["name"]) for p in _packages()]
    assert [n for n in names if n.startswith(CUDA_PREFIXES)] == []


def test_torch_and_torchaudio_come_from_the_cpu_index() -> None:
    # One entry per platform split (+cpu on Linux, plain on macOS): check all.
    torches = [p for p in _packages() if p["name"] in {"torch", "torchaudio"}]
    assert {p["name"] for p in torches} == {"torch", "torchaudio"}
    assert [p["source"] for p in torches] == [{"registry": CPU_INDEX}] * len(torches)
