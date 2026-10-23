"""Rendering with the fake engine: cache hits/misses, pack layout, progress."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path
from typing import Any

from sufler_tts.audio import read_opus_head
from sufler_tts.cache import ClipCache, clip_key
from sufler_tts.engine import FakeEngine
from sufler_tts.render import pack_name, render_script, spoken_lines
from sufler_tts.script import parse_script
from sufler_tts.voices import get_voice

SPOKEN = [1, 3, 4, 5]  # 6 is direction-only text: empty after clean-up


def _render(
    data: dict[str, Any], engine: FakeEngine, cache: ClipCache, out: Path
) -> tuple[Path, list[tuple[int, int]]]:
    seen: list[tuple[int, int]] = []
    path = render_script(
        parse_script(data),
        {},
        engine,
        cache,
        out,
        lambda done, total: seen.append((done, total)),
    )
    return path, seen


def test_spoken_lines_mirror_dart_is_spoken(script_json: dict[str, Any]) -> None:
    lines = spoken_lines(parse_script(script_json))
    assert [i for i, _ in lines] == SPOKEN
    assert dict(lines)[3] == "Witaj, wilku! Co słychać?"


def test_pack_layout_matches_contract(
    script_json: dict[str, Any], engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    path, _ = _render(script_json, engine, cache, tmp_path / "packs")
    assert path.name == "abc123.sufler-audio.zip" == pack_name("abc123")
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        manifest = json.loads(z.read("manifest.json"))
        clip = z.read("audio/1.ogg")
    assert sorted(names) == sorted(
        ["manifest.json", *(f"audio/{i}.ogg" for i in SPOKEN)]
    )
    assert set(manifest) == {"scriptId", "engine", "voices", "lines"}
    assert manifest["scriptId"] == "abc123"
    assert manifest["engine"] == engine.name
    assert set(manifest["voices"]) == {"piaskowy-wilk", "krolowa", "blystek"}
    assert manifest["lines"] == {str(i): f"audio/{i}.ogg" for i in SPOKEN}
    assert clip[:4] == b"OggS"
    assert read_opus_head(clip) == (1, 24000)


def test_second_render_hits_cache(
    script_json: dict[str, Any], engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    _render(script_json, engine, cache, tmp_path / "packs")
    assert len(engine.calls) == len(SPOKEN)
    _render(script_json, engine, cache, tmp_path / "packs")
    assert len(engine.calls) == len(SPOKEN)


def test_edit_rerenders_only_changed_line(
    script_json: dict[str, Any], engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    _render(script_json, engine, cache, tmp_path / "packs")
    script_json["lines"][3]["text"] = "Zmieniony tekst."
    _render(script_json, engine, cache, tmp_path / "packs")
    assert [c[0] for c in engine.calls[len(SPOKEN) :]] == ["Zmieniony tekst."]


def test_cache_key_covers_text_voice_and_engine() -> None:
    a, b = get_voice("f1"), get_voice("m1")
    key = clip_key("Tekst", a, "e@1")
    assert key == clip_key("Tekst", a, "e@1")
    assert len({key, clip_key("Tekst!", a, "e@1"), clip_key("Tekst", b, "e@1")}) == 3
    assert key != clip_key("Tekst", a, "e@2")


def test_progress_counts_every_spoken_line(
    script_json: dict[str, Any], engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    _, seen = _render(script_json, engine, cache, tmp_path / "packs")
    assert seen == [(i, len(SPOKEN)) for i in range(len(SPOKEN) + 1)]


def test_long_line_is_split_and_concatenated(
    script_json: dict[str, Any], engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    sentence = "To jest dość długie zdanie numer {}."
    script_json["lines"][1]["text"] = " ".join(sentence.format(i) for i in range(20))
    _render(script_json, engine, cache, tmp_path / "packs")
    chunks = [c[0] for c in engine.calls if c[0].startswith("To jest")]
    assert len(chunks) > 1
    assert all(len(c) <= 250 for c in chunks)
    assert " ".join(chunks) == script_json["lines"][1]["text"]
