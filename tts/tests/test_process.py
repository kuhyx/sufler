"""The model runs in a child process, so an idle unload really frees the GPU."""

from __future__ import annotations

import pytest

from sufler_tts.process_engine import ProcessEngine
from sufler_tts.voices import get_voice

FAKE = "sufler_tts.engine:FakeEngine"


def test_child_starts_lazily_and_exits_on_close() -> None:
    engine = ProcessEngine(FAKE, "fake@1", watch_every=None)
    assert not engine.loaded
    audio = engine.synthesize("Dzień dobry.", get_voice("f1"), 7)
    assert engine.loaded
    assert audio.dtype.name == "float32"
    assert audio.shape == (1200,)
    engine.close()
    assert not engine.loaded


def test_idle_unload_kills_child_and_next_call_reloads() -> None:
    engine = ProcessEngine(FAKE, "fake@1", idle_s=0.0, watch_every=None)
    engine.synthesize("Raz.", get_voice("m1"), 1)
    assert engine.reaper.check()
    assert not engine.loaded
    engine.synthesize("Dwa.", get_voice("m1"), 1)
    assert engine.loaded
    engine.close()


def test_child_load_error_is_raised_in_parent() -> None:
    engine = ProcessEngine("sufler_tts.engine:Nope", "x@1", watch_every=None)
    with pytest.raises(RuntimeError, match="Nope"):
        engine.synthesize("Raz.", get_voice("m1"), 1)
    assert not engine.loaded
    engine.close()
