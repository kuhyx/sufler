"""What goes to and comes back from `whisper-server`: WAV upload, verbose_json.

Pure functions (no process, no network), so tests feed them captured output.
"""

from __future__ import annotations

import io
import uuid
import wave
from typing import Any

import numpy as np

from sufler_tts.engine import Audio
from sufler_tts.transcribe import STT_RATE, Segment, Word


def wav_bytes(audio: Audio) -> bytes:
    """16 kHz mono float32 samples -> a PCM16 WAV file."""
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(STT_RATE)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


def multipart(fields: dict[str, str], wav: bytes) -> tuple[bytes, str]:
    """(body, boundary) of a form upload: `fields` plus `file` = the WAV."""
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'
        for k, v in fields.items()
    ]
    head = (
        f"--{boundary}\r\nContent-Disposition: form-data; "
        'name="file"; filename="clip.wav"\r\nContent-Type: audio/wav\r\n\r\n'
    )
    body = "".join(parts).encode() + head.encode() + wav
    return body + f"\r\n--{boundary}--\r\n".encode(), boundary


def _segments(body: dict[str, Any]) -> list[list[Any]]:
    """[start, end, text] per segment; one starting mid-word joins the last.

    whisper.cpp may cut a segment inside a word ("dus" | "zno.").
    """
    segs: list[list[Any]] = []
    for seg in body.get("segments", []):
        text = seg["text"]
        if segs and text[:1] not in {" ", ""}:
            segs[-1][1], segs[-1][2] = seg["end"], segs[-1][2] + text
        else:
            segs.append([seg["start"], seg["end"], text])
    return segs


def _words(body: dict[str, Any]) -> list[list[Any]]:
    """[start, end, text] per whole word, from whisper.cpp's BPE pieces.

    A piece with a leading space starts a word; the rest (punctuation too)
    extend it. Times come from the DTW alignment (`t_dtw`, centiseconds, the
    moment a piece ends): a word ends at its last non-punctuation piece and
    starts where the piece before it ended. Token times (`start`/`end`) run
    late at the end of a segment (+0.6 s measured), so they are only the
    fallback: the first word's start, and any piece without a DTW time.
    """
    words: list[list[Any]] = []
    prev: float | None = None
    for seg in body.get("segments", []):
        for piece in seg.get("words", []):
            token: str = piece["word"]
            if token.startswith("[_"):
                continue  # special tokens ([_BEG_], [_TT_n])
            dtw = piece.get("t_dtw", -1)
            done = dtw / 100 if dtw >= 0 else piece["end"]
            if words and not token.startswith(" "):
                if any(c.isalnum() for c in token):
                    words[-1][1] = done
                words[-1][2] += token
            else:
                start = piece["start"] if prev is None else prev
                words.append([start, done, token])
            prev = done
    return words


def parse(body: dict[str, Any], offset: float) -> tuple[list[Segment], list[Word]]:
    """verbose_json -> segments and whole words, shifted by `offset` seconds."""

    def at(t: float) -> float:
        return round(t + offset, 2)

    segments = [
        Segment(at(a), at(b), t.strip()) for a, b, t in _segments(body) if t.strip()
    ]
    words = [
        Word(at(a), at(max(a, b)), t.strip()) for a, b, t in _words(body) if t.strip()
    ]
    return segments, words
