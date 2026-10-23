"""ffmpeg I/O: DSP pitch shift + Opus/Ogg (or WAV) encoding, and OpusHead parsing."""

from __future__ import annotations

import struct
import subprocess
from pathlib import Path

import numpy as np

from sufler_tts.engine import Audio

OUT_RATE = 24_000
GAP_SECONDS = 0.15  # silence between concatenated chunks of one line


def concat(chunks: list[Audio], sample_rate: int) -> Audio:
    """Join chunk clips with a short pause between them."""
    gap = np.zeros(int(sample_rate * GAP_SECONDS), dtype=np.float32)
    parts: list[Audio] = []
    for i, chunk in enumerate(chunks):
        if i:
            parts.append(gap)
        parts.append(chunk.astype(np.float32))
    return np.concatenate(parts) if parts else gap


def _filters(pitch: float) -> list[str]:
    if pitch == 0:
        return []
    ratio = 2.0 ** (pitch / 12.0)
    # Shifted formants on purpose: moving the formants with the pitch is what
    # makes a shifted voice read as a different (smaller/larger) speaker.
    return ["-af", f"rubberband=pitch={ratio:.6f}:formant=shifted"]


def encode(samples: Audio, sample_rate: int, pitch: float, out: Path) -> None:
    """Pitch-shift and write `out` as Ogg/Opus mono 24 kHz, or WAV if `.wav`."""
    codec = (
        ["-c:a", "pcm_s16le"]
        if out.suffix == ".wav"
        else ["-c:a", "libopus", "-b:a", "32k", "-application", "voip"]
    )
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "f32le", "-ar", str(sample_rate), "-ac", "1", "-i", "pipe:0",
        *_filters(pitch),
        "-ac", "1", "-ar", str(OUT_RATE), *codec,
        "-f", "wav" if out.suffix == ".wav" else "ogg", str(out),
    ]  # fmt: skip
    data = np.ascontiguousarray(samples, dtype="<f4").tobytes()
    subprocess.run(cmd, input=data, check=True, capture_output=True)


def decode(path: Path, sample_rate: int = 16_000) -> Audio:
    """Read any audio file as mono float32 at `sample_rate`."""
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
        "-ac", "1", "-ar", str(sample_rate), "-f", "f32le", "pipe:1",
    ]  # fmt: skip
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float32)


def read_opus_head(ogg: bytes) -> tuple[int, int]:
    """(channels, input sample rate) from the OpusHead packet of an Ogg file.

    ffprobe always reports 48 kHz for Opus, so this is the only way to check
    the "mono 24 kHz" contract.
    """
    at = ogg.find(b"OpusHead")
    if at < 0:
        raise ValueError("not an Ogg/Opus stream")
    channels = ogg[at + 9]
    (rate,) = struct.unpack_from("<I", ogg, at + 12)
    return channels, int(rate)
