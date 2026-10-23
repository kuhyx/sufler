"""The relay's edges: RTDB REST over urllib, SSE parsing, setup and startup."""

from __future__ import annotations

import io
import json
import logging
import sys
import urllib.error
import urllib.request
from email.message import Message
from pathlib import Path
from typing import Any

import pytest

from sufler_tts.relay import setup
from sufler_tts.relay.rtdb import Rtdb, RtdbError, parse_sse
from sufler_tts.relay.worker import Relay

TOKEN = "secret-id-token"


class FakeOpener:
    def __init__(self, reply: object = None, fail: Exception | None = None) -> None:
        self.reply, self.fail = reply, fail
        self.seen: list[urllib.request.Request] = []

    def __call__(self, request: urllib.request.Request, timeout: float) -> Any:
        assert timeout > 0
        self.seen.append(request)
        if self.fail is not None:
            raise self.fail
        return io.BytesIO(json.dumps(self.reply).encode())


def _db(opener: FakeOpener) -> Rtdb:
    return Rtdb("https://db.example/", lambda: TOKEN, opener=opener)


def test_rest_calls_live_under_sufler_with_the_token() -> None:
    opener = FakeOpener({"a": True})
    db = _db(opener)
    assert db.get("requests", shallow=True) == {"a": True}
    db.put("results/r1", {"ok": True})
    db.delete("results/r1")
    get, put, delete = opener.seen
    assert get.full_url == (
        f"https://db.example/sufler/requests.json?auth={TOKEN}&shallow=true"
    )
    assert put.get_method() == "PUT" and put.data == b'{"ok": true}'
    assert delete.get_method() == "DELETE"
    assert delete.full_url.startswith("https://db.example/sufler/results/r1.json")


@pytest.mark.parametrize(
    "fail",
    [
        urllib.error.HTTPError("u?auth=" + TOKEN, 401, "no", Message(), None),
        urllib.error.URLError(f"https://x/?auth={TOKEN} unreachable"),
        TimeoutError(),
    ],
)
def test_errors_never_carry_the_url_or_token(fail: Exception) -> None:
    with pytest.raises(RtdbError) as err:
        _db(FakeOpener(fail=fail)).get("requests")
    assert TOKEN not in str(err.value)
    assert str(err.value).startswith("GET requests: ")


def test_parse_sse_events() -> None:
    lines = [
        "event: put",
        'data: {"path": "/", "data": {"r1": {"kind": "explain"}}}',
        "",
        "event: keep-alive",
        "data: null",
        "",
        "event: auth_revoked",
        "data: credential is no longer valid",
        "",
    ]
    assert list(parse_sse(lines)) == [
        ("put", {"path": "/", "data": {"r1": {"kind": "explain"}}}),
        ("keep-alive", None),
        ("auth_revoked", "credential is no longer valid"),
    ]


class NullAssist:
    def explain(self, body: object) -> str:
        raise AssertionError("not called")

    def render_line(self, body: object) -> bytes:
        raise AssertionError("not called")


class CountingRelay(Relay):
    def __init__(self) -> None:
        self.scans = 0

    def scan(self) -> list[Any]:
        self.scans += 1
        return []


def test_stream_events_ring_the_doorbell_until_reconnect() -> None:
    relay = CountingRelay()
    events: list[tuple[str, object]] = [
        ("put", {}),
        ("keep-alive", None),
        ("patch", {}),
        ("auth_revoked", ""),
    ]
    assert relay.on_events(iter([*events, ("put", {})])) == "reconnect"
    assert relay.scans == 2
    with pytest.raises(RtdbError):
        relay.on_events(iter([("cancel", "permission denied")]))


def _config(tmp_path: Path) -> Path:
    path = tmp_path / "firebase.json"
    fields = ("apiKey", "databaseUrl", "projectId", "uid", "email")
    path.write_text(json.dumps({k: f"x-{k}" for k in fields}))
    return path


def test_setup_without_config_or_session_says_why(tmp_path: Path) -> None:
    with pytest.raises(setup.RelaySetupError, match="crdt-sync firebase config"):
        setup.connect(config=tmp_path / "nope.json", auth=tmp_path / "auth.json")
    with pytest.raises(setup.RelaySetupError, match=r"seed_session .*--app sufler"):
        setup.connect(config=_config(tmp_path), auth=tmp_path / "auth.json")


def test_start_is_off_by_env_and_survives_setup_errors(
    caplog: pytest.LogCaptureFixture, tmp_path: Path
) -> None:
    assert setup.start(NullAssist(), env={"SUFLER_RELAY": "0"}) is None
    caplog.set_level(logging.WARNING)

    def broken() -> Rtdb:
        raise setup.RelaySetupError("no signed-in session")

    assert setup.start(NullAssist(), env={}, connect=broken) is None
    assert "relay off: no signed-in session" in caplog.text


def test_device_id_is_persisted(tmp_path: Path) -> None:
    first = setup.device_id(tmp_path)
    assert setup.device_id(tmp_path) == first
    assert (tmp_path / "device_id").read_text().strip() == first


def test_missing_crdt_sync_means_http_only(
    caplog: pytest.LogCaptureFixture, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setitem(sys.modules, "crdt_sync", None)  # an un-synced venv
    caplog.set_level(logging.WARNING)
    assert setup.start(NullAssist(), env={}) is None
    assert "crdt-sync not installed" in caplog.text
