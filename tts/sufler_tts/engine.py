"""The engine seam: what the renderer needs from a TTS model.

Real engines live in `chatterbox_engine.py` (imports torch) and are reached
through `process_engine.py`; tests use `FakeEngine` and never import torch.
"""

from __future__ import annotations

from typing import Protocol

import numpy as np
from numpy.typing import NDArray

from sufler_tts.voices import Voice

Audio = NDArray[np.float32]
SAMPLE_RATE = 24_000


class Engine(Protocol):
    """Text + voice -> mono float32 samples at `sample_rate`."""

    @property
    def name(self) -> str:
        """`<engine>@<version>`; goes into the manifest and the cache key."""
        ...

    @property
    def sample_rate(self) -> int:
        """Output sample rate in Hz."""
        ...

    def synthesize(self, text: str, voice: Voice, seed: int) -> Audio:
        """Render one chunk of cleaned text."""
        ...

    def close(self) -> None:
        """Release the model (and the GPU)."""
        ...


class FakeEngine:
    """Deterministic tones: 50 ms per chunk, pitch keyed by voice. For tests."""

    def __init__(self) -> None:
        """Start with no calls recorded."""
        self.calls: list[tuple[str, str, int]] = []
        self.fail = False
        self.closed = 0

    @property
    def name(self) -> str:
        """Fixed fake engine id."""
        return "fake@1"

    @property
    def sample_rate(self) -> int:
        """Same rate as Chatterbox."""
        return SAMPLE_RATE

    def synthesize(self, text: str, voice: Voice, seed: int) -> Audio:
        """Record the call and return a short sine."""
        if self.fail:
            raise RuntimeError("fake engine failure")
        self.calls.append((text, voice.id, seed))
        t = np.arange(SAMPLE_RATE // 20, dtype=np.float32) / SAMPLE_RATE
        freq = 150.0 + 10.0 * (sum(voice.id.encode()) % 20)
        return (0.3 * np.sin(2 * np.pi * freq * t)).astype(np.float32)

    def close(self) -> None:
        """Count closes."""
        self.closed += 1
