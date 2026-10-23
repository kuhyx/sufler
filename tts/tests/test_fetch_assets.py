"""fetch_assets pins every download to a revision and a sha256."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from sufler_tts import assets, download, fetch_assets

PINNED = re.compile(r"^https://huggingface\.co/[\w-]+/[\w-]+/resolve/[0-9a-f]{40}/")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _record(monkeypatch: pytest.MonkeyPatch) -> list[tuple[str, Path, str]]:
    calls: list[tuple[str, Path, str]] = []

    def fake(url: str, dest: Path, sha256: str) -> bool:
        calls.append((url, dest, sha256))
        return False

    monkeypatch.setattr(download, "fetch", fake)
    return calls


def test_weights_are_pinned_and_land_in_the_weights_dir(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = _record(monkeypatch)
    fetch_assets.fetch_weights([])
    assert {d.name for _, d, _ in calls} == set(fetch_assets.WEIGHTS)
    for url, dest, sha in calls:
        assert PINNED.match(url), url
        assert url.endswith("/" + dest.name)
        assert dest.parent == assets.WEIGHTS
        assert SHA256.match(sha)


def test_piper_voices_are_pinned(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = _record(monkeypatch)
    fetch_assets.fetch_piper([])
    assert len(calls) == 2 * len(fetch_assets.PIPER_QUALITY)
    for url, dest, sha in calls:
        assert PINNED.match(url), url
        assert dest.parent == assets.PIPER_MODELS
        assert SHA256.match(sha)


def test_unknown_weight_name_is_rejected() -> None:
    with pytest.raises(SystemExit):
        fetch_assets.main(["weights", "nope.pt"])
