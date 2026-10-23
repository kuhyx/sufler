"""The PC half of the phone relay: `sufler/requests/{rid}` -> `results/{rid}`.

The phone cannot reach this PC's 127.0.0.1 service, so it PUTs a request
into RTDB and polls for the result (DOCS-contract.md "Relay"). This worker:

* streams `requests` (SSE) only as a doorbell: any event rescans the node,
  and so does a timer every 60 s (a dropped stream loses nothing);
* answers each rid once, on a small thread pool (an explanation never
  waits behind a clip), with the same `Assist` the HTTP endpoints use;
* never re-runs a rid that already has a result, drops requests older than
  10 min of server time unanswered (the phone gave up; no Claude call is
  spent on it), and GCs results and requests older than 24 h;
* beats `presence/{device}` with a server timestamp every 30 s; the beat
  also measures this PC's clock skew, so "10 min old" is server time.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import socket
import threading
import time
from collections.abc import Callable, Iterator
from concurrent.futures import Future, ThreadPoolExecutor
from typing import Any, Final, Protocol

from sufler_tts.assist_error import AssistError
from sufler_tts.relay.rtdb import SERVER_TIME, Db, RtdbError

MAX_AGE_MS: Final = 10 * 60 * 1000
GC_AGE_MS: Final = 24 * 3600 * 1000
BEAT_S: Final = 30.0
RESCAN_S: Final = 60.0
GC_S: Final = 600.0
VERSION: Final = "1"
_RID: Final = re.compile(r"[A-Za-z0-9_-]{16,64}")
_logger = logging.getLogger(__name__)


class AssistLike(Protocol):
    """`assist.Assist`: the two things the phone may ask for."""

    def explain(self, body: object) -> str:
        """Polish explanation text."""
        ...

    def render_line(self, body: object) -> bytes:
        """One line's Ogg clip."""
        ...


class Relay:
    """Serves requests for one PC (`device` = its persisted uuid)."""

    def __init__(
        self,
        db: Db,
        assist: AssistLike,
        device: str,
        *,
        clock: Callable[[], float] = time.time,
        workers: int = 2,
    ) -> None:
        """Bind the database; nothing runs until `run()` or `scan()`."""
        self.db, self.assist, self.device = db, assist, device
        self.clock = clock
        self.skew_ms = 0
        self.started = int(clock() * 1000)
        self._pool = ThreadPoolExecutor(workers, thread_name_prefix="relay")
        self._lock = threading.Lock()
        self._busy: set[str] = set()

    def server_now_ms(self) -> int:
        """RTDB server time as estimated from the last beat."""
        return int(self.clock() * 1000) + self.skew_ms

    def beat(self) -> None:
        """One heartbeat; measures the skew from the resolved server time."""
        sent = self.clock()
        stored = self.db.put(
            f"presence/{self.device}",
            {
                "beat": SERVER_TIME,
                "host": socket.gethostname(),
                "pid": os.getpid(),
                "started": self.started,
                "version": VERSION,
            },
        )
        server = stored.get("beat") if isinstance(stored, dict) else None
        if isinstance(server, int):
            self.skew_ms = server - int((sent + self.clock()) / 2 * 1000)

    def leave(self) -> None:
        """Remove this PC's presence (clean exit): phones show it offline."""
        self.db.delete(f"presence/{self.device}")

    def scan(self) -> list[Future[None]]:
        """Submit every pending request not already in flight."""
        pending = self.db.get("requests")
        if not isinstance(pending, dict):
            return []
        futures = []
        with self._lock:
            for rid, req in pending.items():
                if rid in self._busy:
                    continue
                self._busy.add(rid)
                futures.append(self._pool.submit(self._handle, rid, req))
        return futures

    def _handle(self, rid: str, req: object) -> None:
        try:
            self.handle(rid, req)
        except RtdbError as err:
            _logger.warning("relay request %s failed: %s", rid, err)
        finally:
            with self._lock:
                self._busy.discard(rid)

    def handle(self, rid: str, req: object) -> None:
        """Answer one request (once), then delete it."""
        ts = req.get("ts") if isinstance(req, dict) else None
        fresh = isinstance(ts, int) and self.server_now_ms() - ts <= MAX_AGE_MS
        if _RID.fullmatch(rid) and fresh and self.db.get(f"results/{rid}") is None:
            result = {**self.serve(req), "at": SERVER_TIME}
            self.db.put(f"results/{rid}", result)
        self.db.delete(f"requests/{rid}")

    def serve(self, req: object) -> dict[str, Any]:
        """`{ok, text | audioB64}` or `{ok: false, error}` for one request."""
        kind = req.get("kind") if isinstance(req, dict) else None
        raw = req.get("payload") if isinstance(req, dict) else None
        try:
            if not isinstance(raw, str):
                raise AssistError(400, "payload must be a JSON string")
            try:
                payload = json.loads(raw)
            except ValueError:
                raise AssistError(400, "payload is not JSON") from None
            if kind == "explain":
                return {"ok": True, "text": self.assist.explain(payload)}
            if kind == "render_line":
                clip = self.assist.render_line(payload)
                return {"ok": True, "audioB64": base64.b64encode(clip).decode()}
            raise AssistError(400, f"unknown kind {kind!r}")
        except AssistError as exc:
            return {"ok": False, "error": exc.message}

    def gc(self) -> None:
        """Delete results and requests older than 24 h (server time)."""
        cutoff = self.server_now_ms() - GC_AGE_MS
        for node, stamp in (("results", "at"), ("requests", "ts")):
            keys = self.db.get(node, shallow=True)
            for key in keys if isinstance(keys, dict) else {}:
                at = self.db.get(f"{node}/{key}/{stamp}")
                if not isinstance(at, int) or at < cutoff:
                    self.db.delete(f"{node}/{key}")

    def on_events(self, events: Iterator[tuple[str, object]]) -> str:
        """Ring the doorbell per put/patch; "reconnect" on a revoked token."""
        for event, _ in events:
            if event in {"put", "patch"}:
                self.scan()
            elif event == "auth_revoked":
                return "reconnect"
            elif event == "cancel":
                raise RtdbError("STREAM requests: cancelled by the rules")
        return "reconnect"
