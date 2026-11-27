"""The RTDB relay worker on an in-memory fake database (no network)."""

from __future__ import annotations

import base64
import json
import threading

import pytest
from crdt_sync import E2eCipher
from relay_fakes import (
    DAY_MS,
    RID,
    SEALER,
    FakeAssist,
    FakeDb,
    request,
    result,
    serve,
)

from sufler_tts.assist import AssistError
from sufler_tts.relay.e2e import SEALED, Sealer
from sufler_tts.relay.rtdb import SERVER_TIME
from sufler_tts.relay.worker import Relay, RelayLocked


@pytest.fixture
def db() -> FakeDb:
    return FakeDb()


@pytest.fixture
def assist() -> FakeAssist:
    return FakeAssist()


@pytest.fixture
def relay(db: FakeDb, assist: FakeAssist) -> Relay:
    return Relay(
        db, assist, "pc-uuid", unlock=lambda: SEALER, clock=lambda: db.server_ms / 1000
    )


def test_explain_request_gets_a_result(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    request(db, "explain", {"selection": "wilku", "line": {"text": "Witaj"}})
    serve(relay)
    assert assist.calls == [
        ("explain", {"selection": "wilku", "line": {"text": "Witaj"}})
    ]
    assert result(db) == {
        "ok": True,
        "text": "Znaczy: witam.",
        "at": db.server_ms,
    }
    assert db.get(f"requests/{RID}") is None


def test_render_line_result_carries_base64_audio(db: FakeDb, relay: Relay) -> None:
    request(db, "render_line", {"script": {"id": "x"}, "index": 1})
    serve(relay)
    got = result(db)
    assert got["ok"] is True
    assert base64.b64decode(got["audioB64"]) == b"OggS\x00clip"


def test_failures_become_error_results(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    assist.fail = AssistError(503, "claude timed out after 90 s")
    request(db, "explain", {"selection": "x"})
    request(db, "dance", {}, rid="01J9Z3K6Q4X8M2N5P7R9T1V3W6")
    db.put(
        "requests/01J9Z3K6Q4X8M2N5P7R9T1V3W7",
        {"kind": "explain", "payload": 7, "ts": SERVER_TIME},
    )
    serve(relay)
    results = {rid: result(db, rid) for rid in db.get("results")}
    assert results[RID]["ok"] is False
    assert results[RID]["error"] == "claude timed out after 90 s"
    assert "unknown kind" in results["01J9Z3K6Q4X8M2N5P7R9T1V3W6"]["error"]
    assert "payload" in results["01J9Z3K6Q4X8M2N5P7R9T1V3W7"]["error"]
    assert db.get("requests") is None


def test_answered_rid_is_never_rerun(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    db.put(f"results/{RID}", {"ok": True, "text": "old", "at": SERVER_TIME})
    request(db, "explain", {"selection": "x"})
    serve(relay)
    assert assist.calls == []
    assert db.get(f"results/{RID}")["text"] == "old"
    assert db.get(f"requests/{RID}") is None


def test_stale_requests_expire_and_bad_ones_are_dropped(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    request(db, "explain", {"selection": "x"})
    db.server_ms += 11 * 60 * 1000  # the phone gave up long ago
    request(db, "explain", {"selection": "y"}, rid="not a valid rid at all")
    request(db, "explain", {"selection": "z"}, rid="x")
    serve(relay)
    assert assist.calls == []  # no Claude call for an ask the phone gave up on
    assert result(db) == {"ok": False, "error": "expired", "at": db.server_ms}
    assert set(db.get("results")) == {RID}  # malformed rids get no result
    assert db.get("requests") is None


def test_in_flight_request_is_not_submitted_twice(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    assist.gate = threading.Event()
    request(db, "explain", {"selection": "x"})
    first = relay.scan()
    assert len(first) == 1
    assert relay.scan() == []  # the doorbell rang again mid-call
    assist.gate.set()
    first[0].result(5)
    assert len(assist.calls) == 1


def test_gc_drops_day_old_results_but_leaves_requests_to_scan(
    db: FakeDb, relay: Relay
) -> None:
    db.put("results/01OLD0000000000000000000000", {"ok": True, "at": SERVER_TIME})
    request(db, "explain", {"selection": "x"})
    db.server_ms += DAY_MS + 1
    db.put("results/01NEW0000000000000000000000", {"ok": True, "at": SERVER_TIME})
    db.put("results/01NOAT000000000000000000000", {"ok": True})
    relay.gc()
    assert set(db.get("results")) == {"01NEW0000000000000000000000"}
    assert set(db.get("requests")) == {RID}  # only a scan may retire a request
    serve(relay)
    assert result(db)["error"] == "expired" and db.get("requests") is None


def test_presence_beats_with_server_time_and_leaves(db: FakeDb, relay: Relay) -> None:
    relay.beat()
    node = db.get("presence/pc-uuid")
    assert node["beat"] == db.server_ms
    assert {"host", "pid", "started", "version"} <= set(node)
    relay.leave()
    assert db.get("presence") is None


def test_server_clock_follows_measured_skew(db: FakeDb, assist: FakeAssist) -> None:
    relay = Relay(
        db,
        assist,
        "pc",
        unlock=lambda: SEALER,
        clock=lambda: (db.server_ms - 60_000) / 1000,
    )
    relay.beat()  # this PC is a minute slow
    assert relay.server_now_ms() == db.server_ms
    request(db, "explain", {"selection": "x"})
    serve(relay)
    assert len(assist.calls) == 1  # a fresh request is not "stale" by skew


def test_stored_records_carry_no_text(db: FakeDb, relay: Relay) -> None:
    request(db, "explain", {"selection": "wilku", "line": {"text": "Witaj"}})
    assert set(db.get(f"requests/{RID}")) == {"kind", "deviceId", "ts", SEALED}
    assert "wilku" not in json.dumps(db.get("requests"))
    serve(relay)
    stored = db.get(f"results/{RID}")
    assert set(stored) == {"ok", "at", SEALED}
    assert "witam" not in json.dumps(stored)


def test_an_older_phones_unsealed_request_gets_a_sealed_answer(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    request(db, "explain", {"selection": "x"}, sealed=False)
    serve(relay)
    assert len(assist.calls) == 1
    assert SEALED in db.get(f"results/{RID}")
    assert result(db)["text"] == "Znaczy: witam."


def test_a_request_under_another_key_is_refused_sealed(
    db: FakeDb, relay: Relay, assist: FakeAssist
) -> None:
    other = Sealer(E2eCipher(bytes([9] * 32)))
    path = f"requests/{RID}"
    db.put(
        path,
        other.seal_request(
            path, {"kind": "explain", "payload": "{}", "ts": SERVER_TIME}
        ),
    )
    serve(relay)
    assert assist.calls == []
    assert "another key" in result(db)["error"]


def test_a_moved_blob_does_not_open(db: FakeDb, relay: Relay) -> None:
    request(db, "explain", {"selection": "x"})
    moved = db.get(f"requests/{RID}")
    assert SEALER.open("requests/01J9Z3K6Q4X8M2N5P7R9T1V3W6", moved) is None


def test_locked_pc_neither_beats_nor_answers(db: FakeDb, assist: FakeAssist) -> None:
    tries: list[int] = []

    def locked() -> Sealer:
        tries.append(1)
        raise RelayLocked("no crdt-sync passphrase on this PC")

    relay = Relay(db, assist, "pc", unlock=locked, clock=lambda: db.server_ms / 1000)
    request(db, "explain", {"selection": "x"})
    with pytest.raises(RelayLocked):
        relay.beat()
    with pytest.raises(RelayLocked):
        relay.scan()
    assert db.get("presence") is None and db.get("results") is None
    assert assist.calls == [] and len(tries) == 2  # retried, never cached
