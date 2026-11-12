"""The relay's e2e key and the format shared with the phone (no network)."""

from __future__ import annotations

import json
import stat
from pathlib import Path
from typing import Any

import pytest
from crdt_sync import Argon2Params, E2eCipher

from sufler_tts.relay import e2e, setup
from sufler_tts.relay.worker import RelayLocked

VECTORS = Path(__file__).parents[2] / "test/assist/relay_e2e_vectors.json"
CHEAP = Argon2Params(8, 1, 1)


class Db:
    """Flat path -> value; enough for the header."""

    def __init__(self) -> None:
        self.tree: dict[str, Any] = {}
        self.reads = 0

    def get(self, path: str, *, shallow: bool = False) -> Any:
        self.reads += 1
        return self.tree.get(path)

    def put(self, path: str, value: object) -> Any:
        self.tree[path] = value
        return value

    def delete(self, path: str) -> None:
        self.tree.pop(path, None)


def _vectors() -> dict[str, Any]:
    data: dict[str, Any] = json.loads(VECTORS.read_text())
    return data


def test_the_pc_creates_the_header_and_caches_the_key(tmp_path: Path) -> None:
    db = Db()
    sealer = e2e.unlock(db, "pw", tmp_path, CHEAP)
    header = json.loads(db.tree["e2e"])  # one string leaf at sufler/e2e
    assert header["kdf"] == "argon2id" and "key" not in header
    cached = tmp_path / e2e.KEY_FILE
    assert stat.S_IMODE(cached.stat().st_mode) == 0o600
    # A restart opens from the cache, without the passphrase.
    again = e2e.unlock(db, "", tmp_path)
    blob = sealer.seal_result("results/r", {"ok": True, "text": "x"})
    assert again.open("results/r", blob) == {"ok": True, "text": "x"}


def test_a_cache_for_another_header_is_not_used(tmp_path: Path) -> None:
    e2e.unlock(Db(), "pw", tmp_path, CHEAP)
    with pytest.raises(RelayLocked, match="no crdt-sync passphrase"):
        e2e.unlock(Db(), "", tmp_path)  # a fresh header: the cache is stale


@pytest.mark.parametrize("header", ["not json", {"v": 1}])
def test_wrong_passphrase_or_bad_header_is_locked(header: object) -> None:
    db = Db()
    e2e.unlock(db, "pw", None, CHEAP)
    with pytest.raises(RelayLocked):
        e2e.unlock(db, "other", None, CHEAP)
    db.tree["e2e"] = header
    with pytest.raises(RelayLocked):
        e2e.unlock(db, "pw", None, CHEAP)
    assert db.tree["e2e"] == header  # never overwritten


def test_no_passphrase_and_no_cache_is_locked() -> None:
    db = Db()
    with pytest.raises(RelayLocked):
        e2e.unlock(db, "", None)
    assert db.tree == {}  # no header made without a key


def test_the_phones_records_open_here_and_ours_match_its_format() -> None:
    v = _vectors()
    db = Db()
    db.tree["e2e"] = v["header"]
    sealer = e2e.unlock(db, v["passphrase"], None)
    rid = v["rid"]
    for side in ("dart", "python"):
        assert (
            sealer.open(f"requests/{rid}", v[side]["request"])
            == (v["plain"]["request"])
        )
        assert (
            sealer.open(f"results/{rid}", v[side]["result"]) == (v["plain"]["result"])
        )
    ours = sealer.seal_request(f"requests/{rid}", v["plain"]["request"])
    assert set(ours) == set(v["dart"]["request"])


def test_unlocker_reads_the_shared_password_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import crdt_sync  # noqa: PLC0415

    db = Db()
    unlock = setup.unlocker(db, state_dir=tmp_path)  # type: ignore[arg-type]
    with pytest.raises(RelayLocked):
        unlock()  # conftest points PASSWORD_FILE at a missing file
    password = tmp_path / "password"
    password.write_text("pw\n")
    monkeypatch.setattr(crdt_sync, "PASSWORD_FILE", password)
    assert setup.passphrase() == "pw"
    sealer = setup.unlocker(db, lambda: "pw", tmp_path)()  # type: ignore[arg-type]
    assert isinstance(sealer, e2e.Sealer)
    assert "e2e" in db.tree


def test_an_unknown_cipher_text_reads_as_absent() -> None:
    sealer = e2e.Sealer(E2eCipher(bytes([1] * 32)))
    assert sealer.open("results/r", {"ok": True, e2e.SEALED: "AQ" + "A" * 80}) is None
    assert sealer.open("results/r", {"ok": True, "text": "old"}) == {
        "ok": True,
        "text": "old",
    }
