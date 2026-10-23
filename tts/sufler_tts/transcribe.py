"""The transcriber seam: what POST /transcribe needs from a speech-to-text model.

The real model lives in `whisper_engine.py` (imports ctranslate2) and is reached
through `process_stt.py`; tests use `FakeTranscriber` and never import it.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from importlib.metadata import version
from typing import Any, Protocol

import numpy as np

from sufler_tts.engine import Audio

STT_RATE = 16_000  # Whisper's input rate; every upload is resampled to it
DECODE_TIMEOUT_S = 30.0
MODEL = "large-v3-turbo"


def whisper_name() -> str:
    """`faster-whisper@<ver>/<model>` from package metadata (no model import)."""
    return f"faster-whisper@{version('faster-whisper')}/{MODEL}"


@dataclass(frozen=True)
class Segment:
    """One recognised stretch of speech, in seconds from the clip start."""

    start: float
    end: float
    text: str


@dataclass(frozen=True)
class Transcript:
    """Result of one transcription (the JSON body of POST /transcribe)."""

    text: str
    segments: list[Segment]
    speech_start: float | None
    speech_end: float | None
    engine: str

    def public(self) -> dict[str, Any]:
        """The wire shape from DOCS-contract.md (null bounds when no speech)."""
        return {
            "text": self.text,
            "segments": [
                {"start": s.start, "end": s.end, "text": s.text} for s in self.segments
            ],
            "speechStart": self.speech_start,
            "speechEnd": self.speech_end,
            "engine": self.engine,
        }


class Transcriber(Protocol):
    """Mono 16 kHz float32 samples + language -> `Transcript`."""

    @property
    def name(self) -> str:
        """`faster-whisper@<ver>/<model>`; goes into every response."""
        ...

    def transcribe(self, audio: Audio, language: str) -> Transcript:
        """Recognise the speech in `audio` (16 kHz mono)."""
        ...

    def close(self) -> None:
        """Release the model (and the GPU)."""
        ...


def decode_audio(data: bytes) -> Audio:
    """Any ffmpeg-readable upload (WAV, Ogg/WebM Opus, ...) -> mono 16 kHz.

    Raises `ValueError` for bytes ffmpeg cannot decode or that hold no audio.
    """
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0",
        "-vn", "-ac", "1", "-ar", str(STT_RATE), "-f", "f32le", "pipe:1",
    ]  # fmt: skip
    try:
        done = subprocess.run(
            cmd,
            input=data,
            capture_output=True,
            check=False,
            timeout=DECODE_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired as exc:
        raise ValueError("audio decoding timed out") from exc
    if done.returncode != 0 or len(done.stdout) < 4:
        raise ValueError("undecodable audio")
    return np.frombuffer(done.stdout, dtype="<f4").astype(np.float32)


@dataclass
class FakeTranscriber:
    """Reports clip length and loudness instead of words. For tests."""

    calls: list[tuple[int, str]] = field(default_factory=list)
    fail: bool = False
    closed: int = 0

    @property
    def name(self) -> str:
        """Fixed fake id."""
        return "fake-stt@1"

    def transcribe(self, audio: Audio, language: str) -> Transcript:
        """Record the call; 'speech' is the span where the signal is loud."""
        if self.fail:
            raise RuntimeError("fake transcriber failure")
        self.calls.append((len(audio), language))
        loud = np.flatnonzero(np.abs(audio) > 0.05)
        if loud.size == 0:
            return Transcript("", [], None, None, self.name)
        start, end = loud[0] / STT_RATE, (loud[-1] + 1) / STT_RATE
        text = f"fake {language}"
        segment = Segment(round(start, 2), round(end, 2), text)
        return Transcript(text, [segment], segment.start, segment.end, self.name)

    def close(self) -> None:
        """Count closes."""
        self.closed += 1
