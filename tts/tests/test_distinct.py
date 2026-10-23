"""Distinctness maths for the voice bank (pure numpy, no model)."""

from __future__ import annotations

import math

import numpy as np

from sufler_tts.distinct import Record, distinctness, semitones


def _rec(vid: str, f0: float, emb: list[float], jitter: float = 0.0) -> Record:
    a = np.array(emb, dtype=np.float32)
    b = a + np.float32(jitter)
    return Record(vid, (f0, f0), a / np.linalg.norm(a), b / np.linalg.norm(b))


def test_semitones() -> None:
    assert math.isclose(semitones(220.0, 110.0), 12.0)
    assert math.isclose(semitones(100.0, 100.0 * 2 ** (2 / 12)), 2.0)


def test_f0_gap_passes_and_fails() -> None:
    rows = distinctness(
        [
            _rec("a", 100.0, [1, 0, 0]),
            _rec("b", 100.0 * 2 ** (3 / 12), [1, 0, 0]),
            _rec("c", 100.0 * 2 ** (3.5 / 12), [1, 0, 0]),
        ]
    )
    by_id = {r.id: r for r in rows}
    assert by_id["a"].nearest_f0 == "b"
    assert math.isclose(by_id["a"].f0_gap, 3.0, abs_tol=1e-9)
    assert by_id["a"].distinct
    assert not by_id["b"].distinct  # 0.5 st from c, identical embeddings
    assert not by_id["c"].distinct


def test_embedding_distance_rescues_close_pitch() -> None:
    rows = distinctness(
        [
            _rec("a", 100.0, [1, 0, 0], jitter=0.05),
            _rec("b", 101.0, [0, 1, 0], jitter=0.05),
        ]
    )
    assert all(r.f0_gap < 2 for r in rows)
    assert all(r.emb_gap > r.intra_max for r in rows)
    assert all(r.distinct for r in rows)
