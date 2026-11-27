"""The relay's done-log: an answer survives a failed PUT, a restart and expiry."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from relay_fakes import RID, SEALER, FakeAssist, FakeDb, request, result, serve

from sufler_tts.relay import done, setup
from sufler_tts.relay.done import KEEP_MS, DoneLog
from sufler_tts.relay.rtdb import RtdbError
from sufler_tts.relay.worker import Relay

MIN_MS = 60 * 1000


@pytest.fixture
def db() -> FakeDb:
    return FakeDb()


@pytest.fixture
def assist() -> FakeAssist:
    return FakeAssist()


def _relay(db: FakeDb, assist: FakeAssist) -> Relay:
    return Relay(
        db, assist, "pc-uuid", unlock=lambda: SEALER, clock=lambda: db.server_ms / 1000
    )


def _rows() -> list[dict[str, object]]:
    lines = done.DONE_FILE.read_text().splitlines()
    return [json.loads(line) for line in lines]


def test_the_done_log_is_redirected_in_tests(tmp_path: Path) -> None:
    assert done.DONE_FILE.parent == tmp_path


def test_a_failed_put_is_retried_from_the_log_however_old(
    db: FakeDb, assist: FakeAssist
) -> None:
    relay = _relay(db, assist)
    request(db, "explain", {"selection": "x"})
    db.down = True  # the outage starts after the phone published
    serve(relay)
    assert len(assist.calls) == 1
    assert db.get("results") is None and db.get(f"requests/{RID}") is not None
    assert [row["rid"] for row in _rows()] == [RID]
    db.down = False
    db.server_ms += 30 * MIN_MS  # longer than the 10 min expiry
    serve(relay)
    assert len(assist.calls) == 1  # no second Claude call
    assert result(db)["text"] == "Znaczy: witam."
    assert db.get("requests") is None


def test_the_answer_is_on_disk_before_its_put(db: FakeDb, assist: FakeAssist) -> None:
    seen: list[bool] = []

    def check(path: str) -> None:
        if path.startswith("results/"):
            seen.append(done.DONE_FILE.is_file() and RID in done.DONE_FILE.read_text())

    db.on_put = check
    request(db, "render_line", {"index": 1})
    serve(_relay(db, assist))
    assert seen == [True]


def test_a_restarted_worker_puts_the_saved_answer_without_rerun(
    db: FakeDb, assist: FakeAssist
) -> None:
    request(db, "render_line", {"index": 1})
    db.down = True
    serve(_relay(db, assist))
    db.down = False
    db.server_ms += 11 * MIN_MS
    fresh = FakeAssist()
    serve(_relay(db, fresh))  # a new process: a new log instance, same disk
    assert fresh.calls == []
    assert result(db)["ok"] is True and "audioB64" in result(db)
    assert db.get("requests") is None


def test_an_expired_request_is_deleted_only_after_its_put(
    db: FakeDb, assist: FakeAssist
) -> None:
    relay = _relay(db, assist)
    request(db, "explain", {"selection": "x"})
    db.server_ms += 11 * MIN_MS
    db.down = True
    serve(relay)
    assert db.get(f"requests/{RID}") is not None  # kept until answered
    assert [row["rid"] for row in _rows()] == [RID]
    db.down = False
    serve(relay)
    assert assist.calls == []
    assert result(db)["error"] == "expired"
    assert db.get("requests") is None


def test_a_put_result_is_not_put_again_when_only_the_delete_failed(
    db: FakeDb, assist: FakeAssist, monkeypatch: pytest.MonkeyPatch
) -> None:
    relay = _relay(db, assist)
    request(db, "explain", {"selection": "x"})
    real_delete = db.delete

    def failing(path: str) -> None:
        raise RtdbError(f"DELETE {path}: 503")

    monkeypatch.setattr(db, "delete", failing)
    serve(relay)
    monkeypatch.setattr(db, "delete", real_delete)
    serve(relay)
    assert db.puts.count(f"results/{RID}") == 1 and len(assist.calls) == 1
    assert db.get("requests") is None


def test_settled_rows_leave_memory_and_the_file_on_gc(
    db: FakeDb, assist: FakeAssist
) -> None:
    relay = _relay(db, assist)
    request(db, "explain", {"selection": "x"})
    serve(relay)
    assert relay.done.get(RID) is None
    relay.gc()
    assert _rows() == []


def test_load_drops_rows_past_retention_and_unreadable_lines(tmp_path: Path) -> None:
    path = tmp_path / "log.jsonl"
    now = 10 * KEEP_MS
    rows = [
        {"rid": "old", "at": now - KEEP_MS - 1, "stored": {"ok": True}},
        {"rid": "new", "at": now - 1, "stored": {"ok": True}},
    ]
    lines = [json.dumps(row) for row in rows]
    path.write_text("\n".join([*lines, '{"rid": "torn", "at"']) + "\n")
    log = DoneLog(path, now)
    assert log.get("old") is None and log.get("new") == {"ok": True}
    assert path.read_text() == lines[1] + "\n"


def test_compact_without_a_file_writes_nothing(tmp_path: Path) -> None:
    log = DoneLog(tmp_path / "none.jsonl", 0)
    log.compact(0)
    assert not (tmp_path / "none.jsonl").exists()


def test_an_unwritable_log_is_logged_and_keeps_the_relay_up(
    db: FakeDb,
    assist: FakeAssist,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    (tmp_path / "file").write_text("")
    monkeypatch.setattr(done, "DONE_FILE", tmp_path / "file" / "log.jsonl")
    relay = _relay(db, assist)
    request(db, "explain", {"selection": "x"})
    serve(relay)  # the answer cannot be saved: logged, the request kept
    assert db.get(f"requests/{RID}") is not None
    assert db.get(f"results/{RID}") is None
    assert "relay request" in caplog.text


def test_a_failed_compaction_is_logged_and_results_are_still_gcd(
    db: FakeDb,
    assist: FakeAssist,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    folder = tmp_path / "ro"
    folder.mkdir()
    (folder / "log.jsonl").write_text("")
    monkeypatch.setattr(done, "DONE_FILE", folder / "log.jsonl")
    relay = _relay(db, assist)
    db.put("results/01OLD0000000000000000000000", {"ok": True, "at": 1})
    folder.chmod(0o500)  # the rewrite's tmp file cannot be created
    try:
        relay.gc()  # the GC thread survives a failed compaction
    finally:
        folder.chmod(0o700)
    assert db.get("results") is None
    assert "done-log compaction failed" in caplog.text


def test_start_survives_an_unreadable_log(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    (tmp_path / "log.jsonl").write_text("")
    (tmp_path / "log.jsonl").chmod(0)  # present but unreadable
    monkeypatch.setattr(done, "DONE_FILE", tmp_path / "log.jsonl")
    monkeypatch.setattr(setup, "device_id", lambda: "pc")
    monkeypatch.setattr(setup, "unlocker", lambda db: lambda: SEALER)
    assert setup.start(FakeAssist(), env={}, connect=FakeDb) is None
