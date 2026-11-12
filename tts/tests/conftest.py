"""Shared fixtures: a synthetic script (never text from a real play)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from sufler_tts.cache import ClipCache
from sufler_tts.engine import FakeEngine


def _line(
    index: int, speakers: list[str], text: str, kind: str = "dialogue"
) -> dict[str, Any]:
    return {"index": index, "speakers": speakers, "text": text, "kind": kind}


@pytest.fixture
def script_json() -> dict[str, Any]:
    """Seven lines: dialogue, a heading, a direction, a chorus lyric, a duet."""
    return {
        "id": "abc123",
        "title": "Próba",
        "source": "synthetic.pdf",
        "characters": [
            {"id": "piaskowy-wilk", "name": "Piaskowy Wilk", "aliases": []},
            {"id": "krolowa", "name": "Królowa", "aliases": []},
            {"id": "blystek", "name": "Błystek", "aliases": []},
        ],
        "scenes": [{"id": "scena-1", "title": "Scena 1", "start": 0, "end": 6}],
        "songs": [],
        "lines": [
            _line(0, [], "Scena 1", "heading"),
            _line(1, ["piaskowy-wilk"], "Dzień dobry (Wzdycha) wszystkim."),
            _line(2, [], "Wychodzą.", "direction"),
            _line(3, ["krolowa"], "Witaj,   wilku!\nCo słychać?"),
            _line(4, [], "La la la, śpiewamy.", "song"),
            _line(5, ["blystek", "krolowa"], "Razem!"),
            _line(6, ["blystek"], "(Śmieje się)"),
        ],
    }


@pytest.fixture(autouse=True)
def _no_real_secrets(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """No test reads the real ~/.config/crdt-sync/password (the e2e key)."""
    crdt_sync = _crdt_sync()
    if crdt_sync is not None:
        monkeypatch.setattr(crdt_sync, "PASSWORD_FILE", tmp_path / "no-password")


def _crdt_sync() -> Any:
    try:
        import crdt_sync  # noqa: PLC0415
    except ImportError:
        return None
    return crdt_sync


@pytest.fixture
def engine() -> FakeEngine:
    """A fake engine that records every synthesis call."""
    return FakeEngine()


@pytest.fixture
def cache(tmp_path: Path) -> ClipCache:
    """An empty clip cache in a temp dir."""
    return ClipCache(tmp_path / "cache")
