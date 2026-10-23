"""The RTDB relay worker on an in-memory fake database (no network)."""

from __future__ import annotations

import base64
import json
import threading
from typing import Any

import pytest

from sufler_tts.assist import AssistError
from sufler_tts.relay.rtdb import SERVER_TIME
from sufler_tts.relay.worker import Relay

DAY_MS = 24 * 3600 * 1000


class FakeDb:
    """A JSON tree that behaves like RTDB: server times, no nulls/empties."""

    def __init__(self) -> None:
        self.tree: dict[str, Any] = {}
        self.server_ms = 1_000_000_000_000
        self.puts: list[str] = []

    def _resolve(self, value: Any) -> Any:
        if value == SERVER_TIME:
            return self.server_ms
        if isinstance(value, dict):
            out = {k: self._resolve(v) for k, v in value.items()}
            return {k: v for k, v in out.items() if v not in (None, {}, [])} or None
        if isinstance(value, list):
            return [self._resolve(v) for v in value] or None
        return value

    def _parent(self, path: str, create: bool) -> tuple[dict[str, Any] | None, str]:
        parts = [p for p in path.split("/") if p]
        node: Any = self.tree
        for part in parts[:-1]:
            if not isinstance(node, dict):
                return None, parts[-1]
            if part not in node and create:
                node[part] = {}
            node = node.get(part)
        return (node if isinstance(node, dict) else None), parts[-1]

    def get(self, path: str, *, shallow: bool = False) -> Any:
        parent, key = self._parent(path, create=False)
        value = parent.get(key) if parent is not None else None
        value = json.loads(json.dumps(value))
        if shallow and isinstance(value, dict):
            return dict.fromkeys(value, True)
        return value

    def put(self, path: str, value: object) -> Any:
        self.puts.append(path)
        stored = self._resolve(json.loads(json.dumps(value)))
        parent, key = self._parent(path, create=True)
        assert parent is not None
        if stored is None:
            parent.pop(key, None)
        else:
            parent[key] = stored
        return stored

    def delete(self, path: str) -> None:
        parent, key = self._parent(path, create=False)
        if parent is not None:
            parent.pop(key, None)
        self.tree = self._resolve(self.tree) or {}  # RTDB keeps no empty nodes


class FakeAssist:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []
        self.fail: AssistError | None = None
        self.gate: threading.Event | None = None

    def explain(self, body: object) -> str:
        self.calls.append(("explain", body))
        if self.gate is not None:
            self.gate.wait(5)
        if self.fail is not None:
            raise self.fail
        return "Znaczy: witam."

    def render_line(self, body: object) -> bytes:
        self.calls.append(("render_line", body))
        if self.fail is not None:
            raise self.fail
        return b"OggS\x00clip"


RID = "01J9Z3K6Q4X8M2N5P7R9T1V3W5"


@pytest.fixture
def db() -> FakeDb:
    return FakeDb()


@pytest.fixture
def assist() -> FakeAssist:
    return FakeAssist()


@pytest.fixture
def relay(db: FakeDb, assist: FakeAssist) -> Relay:
    return Relay(db, assist, "pc-uuid", clock=lambda: db.server_ms / 1000)


def _request(db: FakeDb, kind: str, payload: object, rid: str = RID) -> None:
    db.put(
        f"requests/{rid}",
        {
            "kind": kind,
            "payload": json.dumps(payload),
            "deviceId": "phone-uuid",
            "ts": SERVER_TIME,
        },
    )


def _serve(relay: Relay) -> None:
    for future in relay.scan():
        future.result(5)


def test_explain_request_gets_a_result(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    _request(db, "explain", {"selection": "wilku", "line": {"text": "Witaj"}})
    _serve(relay)
    assert assist.calls == [
        ("explain", {"selection": "wilku", "line": {"text": "Witaj"}})
    ]
    assert db.get(f"results/{RID}") == {
        "ok": True,
        "text": "Znaczy: witam.",
        "at": db.server_ms,
    }
    assert db.get(f"requests/{RID}") is None


def test_render_line_result_carries_base64_audio(db: FakeDb, relay: Relay) -> None:
    _request(db, "render_line", {"script": {"id": "x"}, "index": 1})
    _serve(relay)
    result = db.get(f"results/{RID}")
    assert result["ok"] is True
    assert base64.b64decode(result["audioB64"]) == b"OggS\x00clip"


def test_failures_become_error_results(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    assist.fail = AssistError(503, "claude timed out after 90 s")
    _request(db, "explain", {"selection": "x"})
    _request(db, "dance", {}, rid="01J9Z3K6Q4X8M2N5P7R9T1V3W6")
    db.put(
        "requests/01J9Z3K6Q4X8M2N5P7R9T1V3W7",
        {"kind": "explain", "payload": 7, "ts": SERVER_TIME},
    )
    _serve(relay)
    results = db.get("results")
    assert results[RID]["ok"] is False
    assert results[RID]["error"] == "claude timed out after 90 s"
    assert "unknown kind" in results["01J9Z3K6Q4X8M2N5P7R9T1V3W6"]["error"]
    assert "payload" in results["01J9Z3K6Q4X8M2N5P7R9T1V3W7"]["error"]
    assert db.get("requests") is None


def test_answered_rid_is_never_rerun(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    db.put(f"results/{RID}", {"ok": True, "text": "old", "at": SERVER_TIME})
    _request(db, "explain", {"selection": "x"})
    _serve(relay)
    assert assist.calls == []
    assert db.get(f"results/{RID}")["text"] == "old"
    assert db.get(f"requests/{RID}") is None


def test_stale_and_bad_requests_are_dropped_unanswered(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    _request(db, "explain", {"selection": "x"})
    db.server_ms += 11 * 60 * 1000  # the phone gave up long ago
    _request(db, "explain", {"selection": "y"}, rid="not a valid rid at all")
    _request(db, "explain", {"selection": "z"}, rid="x")
    _serve(relay)
    assert assist.calls == []
    assert db.get("requests") is None and db.get("results") is None


def test_in_flight_request_is_not_submitted_twice(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    assist.gate = threading.Event()
    _request(db, "explain", {"selection": "x"})
    first = relay.scan()
    assert len(first) == 1
    assert relay.scan() == []  # the doorbell rang again mid-call
    assist.gate.set()
    first[0].result(5)
    assert len(assist.calls) == 1


def test_gc_drops_day_old_results_and_requests(db: FakeDb, relay: Relay) -> None:
    db.put("results/01OLD0000000000000000000000", {"ok": True, "at": SERVER_TIME})
    db.put("requests/01OLD0000000000000000000001", {"kind": "x", "ts": SERVER_TIME})
    db.server_ms += DAY_MS + 1
    db.put("results/01NEW0000000000000000000000", {"ok": True, "at": SERVER_TIME})
    db.put("results/01NOAT000000000000000000000", {"ok": True})
    relay.gc()
    assert set(db.get("results")) == {"01NEW0000000000000000000000"}
    assert db.get("requests") is None


def test_presence_beats_with_server_time_and_leaves(db: FakeDb, relay: Relay) -> None:
    relay.beat()
    node = db.get("presence/pc-uuid")
    assert node["beat"] == db.server_ms
    assert {"host", "pid", "started", "version"} <= set(node)
    relay.leave()
    assert db.get("presence") is None


def test_server_clock_follows_measured_skew(db: FakeDb, assist: FakeAssist) -> None:
    relay = Relay(db, assist, "pc", clock=lambda: (db.server_ms - 60_000) / 1000)
    relay.beat()  # this PC is a minute slow
    assert relay.server_now_ms() == db.server_ms
    _request(db, "explain", {"selection": "x"})
    _serve(relay)
    assert len(assist.calls) == 1  # a fresh request is not "stale" by skew
