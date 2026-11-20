"""The STT child runs whisper.cpp (Vulkan): fake binaries stand in for it.

`tests/fakes/` holds a fake `whisper-server` (canned verbose_json captured
from the real one) and a fake `whisper-vad-speech-segments`; they go first on
PATH, so the real subprocess, HTTP and WAV code runs without a model or GPU.
"""

from __future__ import annotations

import json
import socket
import sys
from pathlib import Path

import numpy as np
import pytest

from sufler_tts import __main__ as service
from sufler_tts import whispercpp_engine
from sufler_tts.process_stt import ProcessTranscriber
from sufler_tts.transcribe import STT_RATE, whisper_name
from sufler_tts.whispercpp_engine import WhisperCppTranscriber

FAKES = Path(__file__).parent / "fakes"
TOOLS = {
    "whisper-server": "fake_whisper_server.py",
    "whisper-vad-speech-segments": "fake_vad.py",
}
TEXT = "proszę otworzyć okno, ponieważ w tym pokoju jest bardzo duszno."


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
    return port


@pytest.fixture
def models(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    """Empty model files where the engine looks for them."""
    model_dir = tmp_path / "models"
    model_dir.mkdir()
    for name in (whispercpp_engine.MODEL_FILE, whispercpp_engine.VAD_FILE):
        (model_dir / name).touch()
    monkeypatch.setattr(whispercpp_engine, "MODEL_DIR", model_dir)
    return model_dir


@pytest.fixture
def log(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    """Fake tools first on PATH; returns the fake server's request log."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for tool, script in TOOLS.items():
        exe = bin_dir / tool
        exe.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKES / script}" "$@"\n')
        exe.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:/usr/bin")
    path = tmp_path / "requests.jsonl"
    monkeypatch.setenv("FAKE_WHISPER_LOG", str(path))
    return path


def _audio(seconds: float = 6.0) -> np.ndarray:
    return np.full(int(seconds * STT_RATE), 0.1, dtype=np.float32)


@pytest.mark.usefixtures("models")
def test_service_selects_whisper_cpp() -> None:
    assert service.STT_FACTORY == "sufler_tts.whispercpp_engine:WhisperCppTranscriber"
    assert whisper_name().startswith("whisper.cpp@")
    assert whisper_name().endswith("/large-v3-turbo")


@pytest.mark.usefixtures("models")
def test_missing_binary_fails_visibly(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(FileNotFoundError, match=r"whisper-server.*install_tts\.sh"):
        WhisperCppTranscriber(port=_free_port())


@pytest.mark.usefixtures("log")
def test_missing_model_fails_visibly(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(whispercpp_engine, "MODEL_DIR", tmp_path / "nothing")
    with pytest.raises(FileNotFoundError, match=r"ggml-large-v3-turbo\.bin"):
        WhisperCppTranscriber(port=_free_port())


def test_missing_binary_reaches_transcribe_as_an_error(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("PATH", str(tmp_path))  # the spawned child inherits it
    stt = ProcessTranscriber(service.STT_FACTORY, whisper_name(), watch_every=None)
    with pytest.raises(RuntimeError, match=r"failed to load: FileNotFoundError"):
        stt.transcribe(_audio(1.0), "pl")


@pytest.mark.usefixtures("models")
def test_transcribes_with_words_on_the_original_timeline(
    log: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_VAD_SPANS", "1.5-5.25")
    stt = WhisperCppTranscriber(port=_free_port())
    try:
        assert stt.device == "vulkan:Fake GPU 3090"
        result = stt.transcribe(_audio(), "pl")
    finally:
        stt.close()
    assert result.text == TEXT
    assert result.engine == whisper_name()
    # "dus" + "zno." came back as two segments: one segment, one word.
    assert [(s.start, s.end, s.text) for s in result.segments] == [(1.5, 5.16, TEXT)]
    assert [w.word for w in result.words] == TEXT.split()
    # Starts: the first piece's token time, then the DTW end of the piece
    # before; ends: DTW of the last non-punctuation piece ("duszno.": "no").
    assert (result.words[0].start, result.words[0].end) == (1.61, 1.82)
    assert (result.words[2].word, result.words[2].start) == ("okno,", 2.34)
    assert (result.words[3].word, result.words[3].start) == ("ponieważ", 3.0)
    assert (result.speech_start, result.speech_end) == (1.61, 4.86)
    sent = [json.loads(line) for line in log.read_text().splitlines()]
    assert [(r["language"], r["response_format"], r["riff"]) for r in sent] == [
        ("pl", "verbose_json", True)
    ]


@pytest.mark.usefixtures("models")
def test_each_speech_span_is_one_request(
    log: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_VAD_SPANS", "0.0-2.0;3.0-6.0")
    stt = WhisperCppTranscriber(port=_free_port())
    try:
        result = stt.transcribe(_audio(), "de")
    finally:
        stt.close()
    assert result.text == f"{TEXT} {TEXT}"
    assert [s.start for s in result.segments] == [0.0, 3.0]
    assert len(result.words) == 2 * len(TEXT.split())
    assert result.words[len(TEXT.split())].start == 3.11
    assert len(log.read_text().splitlines()) == 2


@pytest.mark.usefixtures("models")
def test_silence_is_an_empty_transcript_without_decoding(
    log: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("FAKE_VAD_SPANS", "")
    stt = WhisperCppTranscriber(port=_free_port())
    try:
        result = stt.transcribe(_audio(), "pl")
    finally:
        stt.close()
    assert (result.text, result.segments, result.words) == ("", [], [])
    assert (result.speech_start, result.speech_end) == (None, None)
    assert not log.exists()


@pytest.mark.usefixtures("models", "log")
@pytest.mark.parametrize(
    ("mode", "error"),
    [("crash", r"exited.*failed to open model"), ("cpu", r"no Vulkan GPU")],
)
def test_server_without_a_gpu_or_model_fails_visibly(
    monkeypatch: pytest.MonkeyPatch, mode: str, error: str
) -> None:
    monkeypatch.setenv("FAKE_WHISPER_MODE", mode)
    with pytest.raises(RuntimeError, match=error):
        WhisperCppTranscriber(port=_free_port())


@pytest.mark.usefixtures("models", "log")
def test_close_stops_the_server() -> None:
    stt = WhisperCppTranscriber(port=_free_port())
    proc = stt.server
    stt.close()
    assert proc.poll() is not None
    stt.close()  # idempotent
