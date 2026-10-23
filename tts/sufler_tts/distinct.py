"""Are the bank voices distinguishable? Pitch and speaker-embedding evidence.

A voice passes when its median F0 is >= 2 semitones from every other voice,
OR its speaker embedding (Chatterbox's own voice encoder, unit norm) is
farther from its nearest neighbour than *any* voice is from itself across two
different sentences. That second bar is self-calibrating: "another voice is
less alike than the same voice saying something else".
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from sufler_tts.engine import Audio

MIN_SEMITONES = 2.0


@dataclass(frozen=True)
class Record:
    """Measurements of one voice on two fixed sentences."""

    id: str
    f0: tuple[float, ...]  # median voiced F0 (Hz) per sentence
    emb_a: Audio
    emb_b: Audio

    @property
    def f0_median(self) -> float:
        """Geometric mean of the per-sentence medians."""
        return math.exp(sum(math.log(f) for f in self.f0) / len(self.f0))

    @property
    def emb(self) -> Audio:
        """Unit-norm mean embedding."""
        mean = self.emb_a + self.emb_b
        return np.asarray(mean / np.linalg.norm(mean), dtype=np.float32)

    @property
    def intra(self) -> float:
        """Cosine distance between the voice's two sentences."""
        return cosine_distance(self.emb_a, self.emb_b)


@dataclass(frozen=True)
class Row:
    """One line of the distinctness report."""

    id: str
    f0: float
    nearest_f0: str
    f0_gap: float
    nearest_emb: str
    emb_gap: float
    intra_max: float

    @property
    def distinct(self) -> bool:
        """Pitch gap OR embedding gap clears its bar."""
        return self.f0_gap >= MIN_SEMITONES or self.emb_gap > self.intra_max


def semitones(a: float, b: float) -> float:
    """Absolute interval between two frequencies, in semitones."""
    return abs(12.0 * math.log2(a / b))


def cosine_distance(a: Audio, b: Audio) -> float:
    """1 - cosine similarity."""
    sim = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
    return 1.0 - sim


def distinctness(records: list[Record]) -> list[Row]:
    """Nearest-neighbour pitch and embedding gaps for every voice."""
    intra_max = max(r.intra for r in records)
    rows: list[Row] = []
    for r in records:
        others = [o for o in records if o.id != r.id]
        near_f0 = min(others, key=lambda o: semitones(r.f0_median, o.f0_median))
        near_emb = min(others, key=lambda o: cosine_distance(r.emb, o.emb))
        rows.append(
            Row(
                r.id,
                r.f0_median,
                near_f0.id,
                semitones(r.f0_median, near_f0.f0_median),
                near_emb.id,
                cosine_distance(r.emb, near_emb.emb),
                intra_max,
            )
        )
    return rows


def format_rows(rows: list[Row]) -> str:
    """Plain-text table for the report."""
    out = ["voice  F0(Hz)  nn-F0  gap(st)  nn-emb  dist   intra-max  ok"]
    out += [
        f"{r.id:<7}{r.f0:7.1f}  {r.nearest_f0:<6}{r.f0_gap:7.2f}  "
        f"{r.nearest_emb:<7}{r.emb_gap:6.3f}  {r.intra_max:8.3f}  "
        f"{'yes' if r.distinct else 'NO'}"
        for r in sorted(rows, key=lambda r: r.f0)
    ]
    return "\n".join(out)
