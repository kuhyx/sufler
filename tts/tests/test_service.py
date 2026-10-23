"""HTTP API over the fake engine, plus job progress and idle unloading."""

from __future__ import annotations

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

from sufler_tts.cache import ClipCache
from sufler_tts.engine import FakeEngine
from sufler_tts.idle import IdleReaper
from sufler_tts.jobs import JobRunner
from sufler_tts.server import make_server


@pytest.fixture
def base_url(engine: FakeEngine, cache: ClipCache, tmp_path: Path) -> Iterator[str]:
    runner = JobRunner(engine, cache, tmp_path / "packs")
    server = make_server(runner, port=0, gpu=lambda: "Fake GPU")
    threading.Thread(target=server.serve_forever, daemon=True).start()
    host, port = server.server_address[:2]
    yield f"http://{host!s}:{port}"
    server.shutdown()
    runner.stop()


def _get(url: str) -> Any:
    with urllib.request.urlopen(url, timeout=5) as r:
        return json.loads(r.read())


def _post(url: str, body: object) -> Any:
    req = urllib.request.Request(url, json.dumps(body).encode(), method="POST")
    with urllib.request.urlopen(req, timeout=5) as r:
        assert r.status == 200  # the Dart RenderClient accepts 200 only
        return json.loads(r.read())


def _wait(url: str) -> dict[str, Any]:
    for _ in range(200):
        job: dict[str, Any] = _get(url)
        if job["state"] in {"done", "error"}:
            return job
        time.sleep(0.02)
    raise AssertionError("job never finished")


def test_binds_loopback_only(base_url: str) -> None:
    assert base_url.startswith("http://127.0.0.1:")


def test_health_and_voices(base_url: str) -> None:
    assert _get(f"{base_url}/health") == {
        "ok": True,
        "engine": "fake@1",
        "gpu": "Fake GPU",
    }
    voices = _get(f"{base_url}/voices")
    assert {"id", "label", "gender"} <= set(voices[0])
    assert len(voices) >= 9


def _manifest_voices(base_url: str) -> Any:
    with urllib.request.urlopen(f"{base_url}/packs/abc123.zip", timeout=5) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        return json.loads(z.read("manifest.json"))["voices"]


def test_render_bare_script_like_dart_client(
    base_url: str, script_json: dict[str, Any]
) -> None:
    job_id = _post(f"{base_url}/render", script_json)["jobId"]
    job = _wait(f"{base_url}/jobs/{job_id}")
    assert job == {"done": 4, "total": 4, "state": "done"}
    with urllib.request.urlopen(f"{base_url}/packs/abc123.zip", timeout=5) as r:
        assert r.read()[:2] == b"PK"
        assert "abc123.sufler-audio.zip" in r.headers["Content-Disposition"]


def test_voice_overrides_via_query(base_url: str, script_json: dict[str, Any]) -> None:
    url = f"{base_url}/render?voices=krolowa:narrator,blystek:f4"
    _wait(f"{base_url}/jobs/{_post(url, script_json)['jobId']}")
    voices = _manifest_voices(base_url)
    assert (voices["krolowa"], voices["blystek"]) == ("narrator", "f4")


def test_wrapped_body_still_accepted(
    base_url: str, script_json: dict[str, Any]
) -> None:
    body = {"script": script_json, "voices": {"krolowa": "m1"}}
    _wait(f"{base_url}/jobs/{_post(f'{base_url}/render', body)['jobId']}")
    assert _manifest_voices(base_url)["krolowa"] == "m1"


def test_bad_requests(base_url: str, script_json: dict[str, Any]) -> None:
    cases = [
        ("", {"id": 1, "lines": []}),
        ("", {"script": script_json, "voices": {"x": "?"}}),
        ("?voices=krolowa:nope", script_json),
        ("?voices=krolowa", script_json),
    ]
    for query, body in cases:
        with pytest.raises(urllib.error.HTTPError) as err:
            _post(f"{base_url}/render{query}", body)
        assert err.value.code == 400
    for path in ("/jobs/nope", "/packs/nope.zip", "/packs/..%2Fx.zip", "/x"):
        with pytest.raises(urllib.error.HTTPError) as err:
            _get(f"{base_url}{path}")
        assert err.value.code == 404


def test_failed_job_reports_error(
    engine: FakeEngine, cache: ClipCache, tmp_path: Path, script_json: dict[str, Any]
) -> None:
    engine.fail = True
    runner = JobRunner(engine, cache, tmp_path / "packs")
    job = runner.submit(script_json, {})
    runner.stop()
    assert job.state == "error"
    assert job.error is not None


def test_idle_reaper_unloads_after_timeout() -> None:
    now = [0.0]
    unloaded: list[float] = []
    reaper = IdleReaper(600.0, lambda: unloaded.append(now[0]), clock=lambda: now[0])
    assert not reaper.check()  # nothing loaded yet
    reaper.touch()
    now[0] = 599.0
    assert not reaper.check()
    reaper.touch()
    now[0] = 1198.0
    assert not reaper.check()
    now[0] = 1200.0
    assert reaper.check()
    assert unloaded == [1200.0]
    now[0] = 9999.0
    assert not reaper.check()  # already unloaded
