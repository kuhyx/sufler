"""Shared by the relay tests: an in-memory RTDB, a fake Assist, the phone's side."""

from __future__ import annotations

import json
import threading
from typing import Any

from crdt_sync import E2eCipher

from sufler_tts.assist import AssistError
from sufler_tts.relay.e2e import Sealer
from sufler_tts.relay.rtdb import SERVER_TIME, RtdbError
from sufler_tts.relay.worker import Relay

DAY_MS = 24 * 3600 * 1000
# The shared key in tests (the phone's tests seal with the same one).
SEALER = Sealer(E2eCipher(bytes([7] * 32)))


class FakeDb:
    """A JSON tree that behaves like RTDB: server times, no nulls/empties."""

    def __init__(self) -> None:
        self.tree: dict[str, Any] = {}
        self.server_ms = 1_000_000_000_000
        self.puts: list[str] = []
        self.down = False  # an outage: every PUT and DELETE fails
        self.on_put: Any = None  # called with the path before each PUT lands

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
        if self.on_put is not None:
            self.on_put(path)
        if self.down:
            raise RtdbError(f"PUT {path}: 503")
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
        if self.down:
            raise RtdbError(f"DELETE {path}: 503")
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


def request(
    db: FakeDb, kind: str, payload: object, rid: str = RID, *, sealed: bool = True
) -> None:
    """Plays the phone: a request as it publishes it (sealed)."""
    path = f"requests/{rid}"
    record = {
        "kind": kind,
        "payload": json.dumps(payload),
        "deviceId": "phone-uuid",
        "ts": SERVER_TIME,
    }
    db.put(path, SEALER.seal_request(path, record) if sealed else record)


def result(db: FakeDb, rid: str = RID) -> Any:
    """A result as the phone reads it (opened)."""
    return SEALER.open(f"results/{rid}", db.get(f"results/{rid}"))


def serve(relay: Relay) -> None:
    for future in relay.scan():
        future.result(5)
