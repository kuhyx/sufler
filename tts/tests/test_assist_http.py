"""POST /explain and POST /render_line over HTTP, on the fake engine."""

from __future__ import annotations

import copy
import io
import json
import threading
import time
import urllib.error
import urllib.request
import zipfile
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest

from sufler_tts.assist import Assist, AssistError
from sufler_tts.cache import ClipCache
from sufler_tts.engine import FakeEngine
from sufler_tts.explain import ExplainRequest
from sufler_tts.jobs import JobRunner
from sufler_tts.server import make_server


class FakeExplainer:
    def __init__(self) -> None:
        self.asked: list[ExplainRequest] = []
        self.fail: AssistError | None = None

    def explain(self, request: ExplainRequest) -> str:
        if self.fail is not None:
            raise self.fail
        self.asked.append(request)
        return f"Wyjaśnienie: {request.selection}"


@pytest.fixture
def explainer() -> FakeExplainer:
    return FakeExplainer()


@pytest.fixture
def base_url(
    engine: FakeEngine, cache: ClipCache, tmp_path: Path, explainer: FakeExplainer
) -> Iterator[str]:
    runner = JobRunner(engine, cache, tmp_path / "packs")
    assist = Assist(engine, cache, tmp_path / "packs", explainer)
    server = make_server(runner, port=0, gpu=lambda: None, assist=assist)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    host, port = server.server_address[:2]
    yield f"http://{host!s}:{port}"
    server.shutdown()
    runner.stop()


def _post(url: str, body: object) -> tuple[int, str, bytes]:
    req = urllib.request.Request(url, json.dumps(body).encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.headers["Content-Type"], r.read()
    except urllib.error.HTTPError as err:
        return err.code, err.headers["Content-Type"], err.read()


def _explain_body() -> dict[str, Any]:
    return {
        "scriptId": "abc123",
        "title": "Próba",
        "selection": "wilku",
        "line": {"index": 3, "speakers": ["Królowa"], "text": "Witaj, wilku!"},
    }


def test_explain_returns_text(base_url: str, explainer: FakeExplainer) -> None:
    status, kind, body = _post(f"{base_url}/explain", _explain_body())
    assert (status, kind) == (200, "application/json; charset=utf-8")
    assert json.loads(body) == {"text": "Wyjaśnienie: wilku"}
    assert explainer.asked[0].line.text == "Witaj, wilku!"


def test_explain_errors(base_url: str, explainer: FakeExplainer) -> None:
    status, _, body = _post(f"{base_url}/explain", {"selection": ""})
    assert status == 400 and "error" in json.loads(body)
    explainer.fail = AssistError(503, "claude timed out after 90 s")
    status, _, body = _post(f"{base_url}/explain", _explain_body())
    assert (status, json.loads(body)) == (503, {"error": "claude timed out after 90 s"})


def test_explain_without_explainer_is_503(
    engine: FakeEngine, cache: ClipCache, tmp_path: Path
) -> None:
    assist = Assist(engine, cache, tmp_path / "packs", None)
    with pytest.raises(AssistError) as err:
        assist.explain(_explain_body())
    assert err.value.status == 503


def _pack_clip(base_url: str, index: int) -> tuple[bytes, dict[str, str]]:
    with urllib.request.urlopen(f"{base_url}/packs/abc123.zip", timeout=5) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        voices = json.loads(z.read("manifest.json"))["voices"]
        return z.read(f"audio/{index}.ogg"), voices


def _render_pack(base_url: str, script_json: dict[str, Any], query: str = "") -> None:
    status, _, body = _post(f"{base_url}/render{query}", script_json)
    assert status == 200
    job_url = f"{base_url}/jobs/{json.loads(body)['jobId']}"
    for _ in range(200):
        with urllib.request.urlopen(job_url, timeout=5) as r:
            if json.loads(r.read())["state"] == "done":
                return
        time.sleep(0.02)
    raise AssertionError("pack never finished")


def test_render_line_matches_the_pack_clip(
    base_url: str, script_json: dict[str, Any], engine: FakeEngine
) -> None:
    _render_pack(base_url, script_json)
    calls = len(engine.calls)
    status, kind, clip = _post(
        f"{base_url}/render_line", {"script": script_json, "index": 3}
    )
    assert (status, kind) == (200, "audio/ogg")
    assert clip == _pack_clip(base_url, 3)[0]
    assert len(engine.calls) == calls  # straight from the clip cache


def test_render_line_after_an_edit_uses_the_pack_voice(
    base_url: str, script_json: dict[str, Any], engine: FakeEngine
) -> None:
    pack = copy.deepcopy(script_json)
    # The pack was rendered with Królowa overridden to m1 (an older client).
    _render_pack(base_url, pack, "?voices=krolowa:m1")
    voices = _pack_clip(base_url, 3)[1]
    assert voices["krolowa"] == "m1"
    edited = copy.deepcopy(script_json)
    edited["lines"][3]["text"] = "Witaj, wilku! Zmiana."
    status, _, clip = _post(f"{base_url}/render_line", {"script": edited, "index": 3})
    assert status == 200 and clip[:4] == b"OggS"
    text, voice, _ = engine.calls[-1]
    assert text == "Witaj, wilku! Zmiana."
    assert voice == voices["krolowa"]


def test_render_line_without_a_pack_uses_the_default_assignment(
    base_url: str, script_json: dict[str, Any], engine: FakeEngine
) -> None:
    status, _, clip = _post(
        f"{base_url}/render_line", {"script": script_json, "index": 1}
    )
    assert status == 200 and clip[:4] == b"OggS"
    _render_pack(base_url, script_json)
    assert clip == _pack_clip(base_url, 1)[0]


@pytest.mark.parametrize(
    "body",
    [
        {"script": None, "index": 1},
        {"script": {"id": "x"}, "index": 1},
        {"index": "1"},
        {"index": 99},
        {"index": 2},  # a direction: nothing to say
        {"index": 6},  # only a stage direction left after cleaning
    ],
)
def test_render_line_rejects(
    base_url: str, script_json: dict[str, Any], body: dict[str, Any]
) -> None:
    body.setdefault("script", script_json)
    status, _, raw = _post(f"{base_url}/render_line", body)
    assert status == 400 and "error" in json.loads(raw)


def test_render_line_engine_failure_is_500(
    base_url: str, script_json: dict[str, Any], engine: FakeEngine
) -> None:
    engine.fail = True
    status, _, raw = _post(
        f"{base_url}/render_line", {"script": script_json, "index": 1}
    )
    assert status == 500 and "fake engine failure" in json.loads(raw)["error"]
