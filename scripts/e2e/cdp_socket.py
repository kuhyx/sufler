"""Chrome DevTools Protocol transport for the sufler desktop E2E flows.

Finds the scratch browser's websocket endpoints over
``--remote-debugging-port`` and speaks numbered CDP commands on one
websocket, buffering events for later waits. :mod:`cdp` builds the
app-page driver (find, click, type) on top of this.
"""

from __future__ import annotations

import json
import time
import urllib.request
from typing import Any

import websocket

Json = dict[str, Any]


class CdpError(RuntimeError):
    """Chrome answered with an error, or a wait ran out."""


def endpoints(port: int) -> tuple[str, str]:
    """(browser websocket, first app page websocket) of the browser on ``port``."""
    base = f"http://127.0.0.1:{port}"
    with urllib.request.urlopen(f"{base}/json/version", timeout=5) as resp:
        browser = json.load(resp)["webSocketDebuggerUrl"]
    with urllib.request.urlopen(f"{base}/json", timeout=5) as resp:
        pages = [t for t in json.load(resp) if t.get("type") == "page"]
    if not pages:
        msg = "browser has no page target"
        raise CdpError(msg)
    return browser, pages[0]["webSocketDebuggerUrl"]


class Socket:
    """One CDP websocket: numbered commands, events buffered for waits."""

    def __init__(self, url: str) -> None:
        self._ws = websocket.create_connection(url, timeout=30, suppress_origin=True)
        self._next = 0
        self.events: list[Json] = []

    def call(self, method: str, **params: object) -> Json:
        self._next += 1
        msg_id = self._next
        self._ws.send(json.dumps({"id": msg_id, "method": method, "params": params}))
        while True:
            reply: Json = json.loads(self._ws.recv())
            if reply.get("id") == msg_id:
                if "error" in reply:
                    msg = f"{method}: {reply['error']}"
                    raise CdpError(msg)
                result: Json = reply.get("result", {})
                return result
            if "method" in reply:
                self.events.append(reply)

    def pump(self, seconds: float) -> None:
        """Read events for up to ``seconds``."""
        deadline = time.monotonic() + seconds
        while (left := deadline - time.monotonic()) > 0:
            self._ws.settimeout(left)
            try:
                reply = json.loads(self._ws.recv())
            except websocket.WebSocketTimeoutException:
                break
            if "method" in reply:
                self.events.append(reply)
        self._ws.settimeout(30)

    def wait_event(self, method: str, timeout: float, pred: Any = None) -> Json:
        """The first buffered or incoming ``method`` event matching ``pred``."""
        deadline = time.monotonic() + timeout
        while True:
            for e in self.events:
                if e["method"] == method and (pred is None or pred(e["params"])):
                    self.events.remove(e)
                    return e["params"]  # type: ignore[no-any-return]
            if time.monotonic() >= deadline:
                msg = f"no {method} event within {timeout:.0f} s"
                raise CdpError(msg)
            self.pump(min(0.5, deadline - time.monotonic()))

    def close(self) -> None:
        self._ws.close()
