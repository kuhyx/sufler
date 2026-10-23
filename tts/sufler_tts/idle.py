"""Unload the model after a stretch of idleness: the GPU is shared with games."""

from __future__ import annotations

import threading
import time
from collections.abc import Callable

IDLE_SECONDS = 600.0


class IdleReaper:
    """Calls `on_idle` once when `idle_s` pass without a `touch()`."""

    def __init__(
        self,
        idle_s: float,
        on_idle: Callable[[], None],
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        """Nothing counts as loaded until the first `touch()`."""
        self.idle_s = idle_s
        self.on_idle = on_idle
        self.clock = clock
        self._last: float | None = None
        self._lock = threading.Lock()

    def touch(self) -> None:
        """Mark the resource as loaded and just used."""
        with self._lock:
            self._last = self.clock()

    def check(self) -> bool:
        """Unload if idle for long enough; True when it just did."""
        with self._lock:
            if self._last is None or self.clock() - self._last < self.idle_s:
                return False
            self._last = None
        self.on_idle()
        return True

    def watch(self, stop: threading.Event, every: float = 15.0) -> None:
        """Poll `check()` until `stop` is set (run in a daemon thread)."""
        while not stop.wait(every):
            self.check()
