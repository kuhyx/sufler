"""The relay's done-log: rid -> the sealed result it was answered with.

One JSON line per answered rid in `<data>/relay-done.jsonl`, appended and
fsynced before the result PUT. A rescan (or a restarted worker) that finds
the rid here re-PUTs the saved result instead of calling Claude or the TTS
engine again, however old the request is by then. Results are stored sealed
(`relay/e2e.py`), so no answer text lands on disk in the clear.

Bounded: a rid whose request was deleted is settled (dropped from memory),
and `compact()` (every GC tick, and on load) rewrites the file with only the
unsettled rows younger than `KEEP_MS`. A request that old is past the 10 min
expiry, so losing its row can only turn it into an `expired` answer, never a
second run.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from typing import TYPE_CHECKING, Any, Final

from sufler_tts.assets import DATA

if TYPE_CHECKING:
    from pathlib import Path

DONE_FILE: Final = DATA / "relay-done.jsonl"
KEEP_MS: Final = 48 * 3600 * 1000  # twice the 24 h result GC
_logger = logging.getLogger(__name__)


class DoneLog:
    """Sealed results by rid, on disk at `path` until settled or expired."""

    def __init__(self, path: Path, now_ms: int) -> None:
        """Load `path` (skipping unreadable lines), then compact it."""
        self.path = path
        self._lock = threading.Lock()
        self._rows: dict[str, tuple[int, dict[str, Any]]] = {}
        lines = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
        for line in lines:
            try:
                row = json.loads(line)
                rid, at, stored = str(row["rid"]), int(row["at"]), dict(row["stored"])
            except (ValueError, KeyError, TypeError) as err:
                _logger.warning("relay done-log line skipped: %s", err)
                continue
            self._rows[rid] = (at, stored)
        if lines:
            self.compact(now_ms)

    def get(self, rid: str) -> dict[str, Any] | None:
        """The sealed result saved for `rid`, or None."""
        with self._lock:
            row = self._rows.get(rid)
        return row[1] if row else None

    def add(self, rid: str, stored: dict[str, Any], now_ms: int) -> dict[str, Any]:
        """Append `rid` -> `stored` and fsync it; return `stored`."""
        line = json.dumps({"rid": rid, "at": now_ms, "stored": stored})
        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            self._rows[rid] = (now_ms, stored)
        return stored

    def settle(self, rid: str) -> None:
        """Forget `rid`: its request is gone, so it is never asked again."""
        with self._lock:
            self._rows.pop(rid, None)

    def compact(self, now_ms: int) -> None:
        """Rewrite the file with the unsettled rows younger than `KEEP_MS`."""
        cutoff = now_ms - KEEP_MS
        with self._lock:
            self._rows = {r: row for r, row in self._rows.items() if row[0] >= cutoff}
            if not self.path.exists():
                return
            text = "".join(
                json.dumps({"rid": rid, "at": at, "stored": stored}) + "\n"
                for rid, (at, stored) in self._rows.items()
            )
            tmp = self.path.with_name(f".{self.path.name}.tmp")
            with tmp.open("w", encoding="utf-8") as handle:
                handle.write(text)
                handle.flush()
                os.fsync(handle.fileno())
            tmp.replace(self.path)
