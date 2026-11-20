"""Chatterbox picks its device itself and never requires CUDA.

torch is the CPU build (no nvidia wheels), so Chatterbox lands on "cpu" unless
a CUDA torch is installed. STT (whisper.cpp, Vulkan): test_whispercpp.py.
"""

from __future__ import annotations

import importlib
import types
from pathlib import Path
from typing import ClassVar

import pytest
import torch

from sufler_tts import chatterbox_engine


class FakeTTS:
    """Stands in for `ChatterboxMultilingualTTS`; records the load device."""

    devices: ClassVar[list[str]] = []  # class-level call log

    def __init__(self) -> None:
        self.conds = object()

    @classmethod
    def from_local(cls, _path: Path, device: str) -> FakeTTS:
        cls.devices.append(device)
        return cls()


@pytest.fixture
def fake_chatterbox(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    (tmp_path / "t3_mtl23ls_v2.safetensors").touch()
    monkeypatch.setattr(chatterbox_engine, "WEIGHTS", tmp_path)
    mtl = types.SimpleNamespace(ChatterboxMultilingualTTS=FakeTTS)
    monkeypatch.setattr(importlib, "import_module", lambda _: mtl)
    FakeTTS.devices = []


@pytest.mark.parametrize(("cuda", "want"), [(False, "cpu"), (True, "cuda")])
def test_chatterbox_default_device_follows_torch(
    monkeypatch: pytest.MonkeyPatch, cuda: bool, want: str
) -> None:
    monkeypatch.setattr(torch.cuda, "is_available", lambda: cuda)
    assert chatterbox_engine.default_device() == want


@pytest.mark.usefixtures("fake_chatterbox")
def test_chatterbox_without_cuda_loads_and_closes_on_cpu(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(torch.cuda, "is_available", lambda: False)
    engine = chatterbox_engine.ChatterboxEngine()
    assert (engine.device, FakeTTS.devices) == ("cpu", ["cpu"])
    engine.close()  # no CUDA call may raise on a CPU-only torch
