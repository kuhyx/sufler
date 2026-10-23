"""A repeated POST /render for a script already queued or running joins that job."""

from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Any

from sufler_tts.cache import ClipCache
from sufler_tts.engine import Audio, FakeEngine
from sufler_tts.jobs import JobRunner
from sufler_tts.voices import Voice


class GatedEngine(FakeEngine):
    """Blocks every synthesis until `gate` is set, so jobs stay in flight."""

    def __init__(self) -> None:
        super().__init__()
        self.gate = threading.Event()

    def synthesize(self, text: str, voice: Voice, seed: int) -> Audio:
        self.gate.wait(5)
        return super().synthesize(text, voice, seed)


def _runner(engine: FakeEngine, cache: ClipCache, tmp_path: Path) -> JobRunner:
    return JobRunner(engine, cache, tmp_path / "packs")


def test_same_script_in_flight_returns_the_existing_job(
    cache: ClipCache, tmp_path: Path, script_json: dict[str, Any]
) -> None:
    engine = GatedEngine()
    runner = _runner(engine, cache, tmp_path)
    first = runner.submit(script_json, {})
    again = runner.submit(script_json, {})  # first is running or queued
    assert again is first
    engine.gate.set()
    runner.stop()
    assert first.state == "done"
    calls = len(engine.calls)
    assert calls == len({(t, v) for t, v, _ in engine.calls})  # rendered once


def test_different_overrides_or_script_get_their_own_job(
    cache: ClipCache, tmp_path: Path, script_json: dict[str, Any]
) -> None:
    engine = GatedEngine()
    runner = _runner(engine, cache, tmp_path)
    first = runner.submit(script_json, {})
    other_voices = runner.submit(script_json, {"krolowa": "f2"})
    other_script = runner.submit({**script_json, "id": "xyz789"}, {})
    assert len({first.id, other_voices.id, other_script.id}) == 3
    engine.gate.set()
    runner.stop()


def test_finished_job_is_not_reused(
    engine: FakeEngine, cache: ClipCache, tmp_path: Path, script_json: dict[str, Any]
) -> None:
    runner = _runner(engine, cache, tmp_path)
    first = runner.submit(script_json, {})
    for _ in range(250):
        if first.state == "done":
            break
        time.sleep(0.02)
    second = runner.submit(script_json, {})  # same runner, first already done
    runner.stop()
    assert first.state == second.state == "done"
    assert second.id != first.id
