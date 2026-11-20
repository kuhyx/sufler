"""Both model children pick their device themselves and never require CUDA.

torch is the CPU build (no nvidia wheels), so Chatterbox lands on "cpu" unless
a CUDA torch is installed. faster-whisper's ctranslate2 still sees the GPU
through the driver, but without a CUDA 12 cuBLAS it would fail on first use:
it goes to the GPU only when that library actually loads.
"""

from __future__ import annotations

import ctypes
import importlib
import importlib.util
import types
from pathlib import Path
from typing import ClassVar

import pytest
import torch

from sufler_tts import chatterbox_engine, whisper_engine


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


class FakeCT2:
    """`ctranslate2` with a configurable visible GPU count."""

    def __init__(self, gpus: int) -> None:
        self.gpus = gpus

    def get_cuda_device_count(self) -> int:
        return self.gpus


@pytest.mark.parametrize(
    ("cublas", "gpus", "want"),
    [(False, 1, "cpu"), (True, 0, "cpu"), (True, 1, "cuda")],
)
def test_whisper_needs_cublas12_and_a_gpu_for_cuda(
    monkeypatch: pytest.MonkeyPatch, cublas: bool, gpus: int, want: str
) -> None:
    monkeypatch.setattr(whisper_engine, "preload_cublas12", lambda: cublas)
    monkeypatch.setattr(importlib, "import_module", lambda _: FakeCT2(gpus))
    assert whisper_engine.default_device() == want


def _no_nvidia_package(_name: str) -> None:
    raise ModuleNotFoundError("No module named 'nvidia'")


@pytest.mark.parametrize("find_spec", [lambda _: None, _no_nvidia_package])
def test_preload_cublas12_is_false_when_the_library_is_missing(
    monkeypatch: pytest.MonkeyPatch, find_spec: object
) -> None:
    # find_spec raises (not None) when the `nvidia` parent is not installed.
    monkeypatch.setattr(importlib.util, "find_spec", find_spec)

    def missing(name: str, mode: int = 0) -> None:
        raise OSError(f"{name}: cannot open shared object file")

    monkeypatch.setattr(ctypes, "CDLL", missing)
    assert whisper_engine.preload_cublas12() is False


def test_preload_cublas12_loads_the_wheel_by_path(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    spec = types.SimpleNamespace(submodule_search_locations=[str(tmp_path)])
    monkeypatch.setattr(importlib.util, "find_spec", lambda _: spec)
    loaded: list[str] = []
    monkeypatch.setattr(ctypes, "CDLL", lambda name, mode=0: loaded.append(name))
    assert whisper_engine.preload_cublas12() is True
    assert loaded == [
        str(tmp_path / "lib" / "libcublasLt.so.12"),
        str(tmp_path / "lib" / "libcublas.so.12"),
    ]


@pytest.mark.parametrize(("device", "compute"), [("cpu", "int8"), ("cuda", "float16")])
def test_whisper_compute_type_follows_the_device(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, device: str, compute: str
) -> None:
    (tmp_path / "model.bin").touch()
    monkeypatch.setattr(whisper_engine, "WHISPER_DIR", tmp_path)
    monkeypatch.setattr(whisper_engine, "default_device", lambda: device)
    monkeypatch.setattr(whisper_engine, "preload_cublas12", lambda: True)
    seen: dict[str, str] = {}

    def model(_path: str, device: str, compute_type: str) -> object:
        seen.update(device=device, compute_type=compute_type)
        return object()

    fw = types.SimpleNamespace(WhisperModel=model)
    monkeypatch.setattr(importlib, "import_module", lambda _: fw)
    whisper_engine.WhisperTranscriber()
    assert seen == {"device": device, "compute_type": compute}
