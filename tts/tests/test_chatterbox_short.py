"""Chatterbox emits zero speech tokens for some very short texts ("Co?", "R.").

The engine retries once with a leading dash (measured to fix every such case
on the real model), then falls back to short silence; any other error stays
fatal. The model is faked: these tests never touch the GPU.
"""

from __future__ import annotations

import pytest
import torch

from sufler_tts.chatterbox_engine import EMPTY_SPEECH, ChatterboxEngine
from sufler_tts.engine import SAMPLE_RATE
from sufler_tts.voices import get_voice

EMPTY = IndexError("max(): Expected reduction dim 1 to have non-zero size.")


class FakeModel:
    """`generate` raises for every text in `fails`; records what it was asked."""

    def __init__(self, fails: set[str], error: Exception = EMPTY) -> None:
        self.fails, self.error, self.asked = fails, error, list[str]()
        self.conds = object()

    def generate(self, text: str, *_args: object, **_kw: object) -> torch.Tensor:
        self.asked.append(text)
        if text in self.fails:
            raise self.error
        return torch.ones(1, 2400)

    def prepare_conditionals(self, *_args: object) -> None:
        pass


def _engine(model: FakeModel) -> ChatterboxEngine:
    engine = object.__new__(ChatterboxEngine)
    engine.device = "cpu"
    engine.model = model
    engine._conds = {"default": model.conds}
    return engine


def test_short_text_retries_with_a_leading_dash() -> None:
    model = FakeModel({"Co?"})
    audio = _engine(model).synthesize("Co?", get_voice("narrator"), 1)
    assert model.asked == ["Co?", "\u2013 Co?"]
    assert audio.shape == (2400,)


def test_falls_back_to_silence_when_the_retry_is_empty_too() -> None:
    model = FakeModel({"R.", "\u2013 R."})
    audio = _engine(model).synthesize("R.", get_voice("narrator"), 1)
    assert len(audio) == round(EMPTY_SPEECH * SAMPLE_RATE)
    assert not audio.any()


def test_other_errors_stay_fatal() -> None:
    model = FakeModel({"Tak!"}, RuntimeError("CUDA out of memory"))
    with pytest.raises(RuntimeError, match="out of memory"):
        _engine(model).synthesize("Tak!", get_voice("narrator"), 1)
    assert model.asked == ["Tak!"]
