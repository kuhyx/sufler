"""Chrome DevTools Protocol client for the sufler desktop E2E flows.

Attaches over ``--remote-debugging-port`` to the scratch browser that
``scripts/e2e_desktop.sh up`` started on the invisible Xvfb display, so the
browser outlives each flow (one flow per < 60 s call). Flutter web exposes
its semantics tree as DOM nodes once enabled; :meth:`Cdp.find` locates a node
by label and :meth:`Cdp.click` taps it with real (trusted) mouse events.
Pattern adapted from ~/src/tutor/scripts/e2e_cdp.py (pipe transport there).
"""

from __future__ import annotations

import base64
import json
import time
from pathlib import Path
from typing import Final

from cdp_socket import CdpError, Json, Socket, endpoints

_HERE: Final = Path(__file__).parent
_PAGE_JS: Final = (_HERE / "page.js").read_text(encoding="utf-8")
INSTRUMENT_JS: Final = (_HERE / "instrument.js").read_text(encoding="utf-8")


class Cdp:
    """The app page plus the browser target of one scratch browser."""

    def __init__(self, port: int) -> None:
        """Connect to the browser listening on ``port``."""
        browser_url, page_url = endpoints(port)
        self.browser = Socket(browser_url)
        self.page = Socket(page_url)
        self.page.call("Runtime.enable")
        self.page.call("Page.enable")

    def close(self) -> None:
        """Drop both websockets (the browser keeps running)."""
        self.page.close()
        self.browser.close()

    def evaluate(self, expression: str, *, wait: bool = False) -> object:
        """The JSON value of ``expression`` (awaited when ``wait``)."""
        out = self.page.call(
            "Runtime.evaluate",
            expression=expression,
            returnByValue=True,
            awaitPromise=wait,
        )
        if "exceptionDetails" in out:
            raise CdpError(str(out["exceptionDetails"])[:300])
        return out.get("result", {}).get("value")

    def helper(self, call: str, *, wait: bool = False) -> object:
        """Evaluate ``(<page.js>).<call>`` in the page."""
        return self.evaluate(f"({_PAGE_JS}).{call}", wait=wait)

    def reload_instrumented(self) -> None:
        """Reload the app with the audio probe injected before boot."""
        self.page.call("Page.addScriptToEvaluateOnNewDocument", source=INSTRUMENT_JS)
        self.page.call("Page.reload", ignoreCache=True)
        self.page.wait_event("Page.loadEventFired", 20)

    def enable_semantics(self, timeout: float = 20) -> None:
        """Turn Flutter's semantics DOM on (once the app has booted)."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if (self.helper("enableSemantics()") or 0) > 1:  # type: ignore[operator]
                return
            time.sleep(0.3)
        msg = "Flutter semantics never appeared (app did not boot?)"
        raise CdpError(msg)

    def find(self, label: str) -> Json | None:
        """Centre and text of the node labelled ``label`` (prefix/substring)."""
        hit = self.helper(f"find({json.dumps(label)})")
        return hit if isinstance(hit, dict) else None

    def wait_for(self, label: str, timeout: float = 10) -> Json:
        """Poll :meth:`find` until it hits; raise after ``timeout``."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if hit := self.find(label):
                return hit
            self.page.pump(0.25)
        msg = f'"{label}" not on screen within {timeout:.0f} s'
        raise CdpError(msg)

    def text(self) -> str:
        """Every semantics label on the page, one per line."""
        out = self.helper("text()")
        return out if isinstance(out, str) else ""

    def click(self, hit: Json) -> None:
        """A real left click (move, press, release) at ``hit``'s centre."""
        if not hit["visible"]:
            self.scroll_to(hit)
            hit = self.find(hit["text"]) or hit
        point = {"x": hit["x"], "y": hit["y"]}
        self.page.call("Input.dispatchMouseEvent", type="mouseMoved", **point)
        for kind in ("mousePressed", "mouseReleased"):
            self.page.call(
                "Input.dispatchMouseEvent",
                type=kind,
                button="left",
                clickCount=1,
                **point,
            )

    def tap(self, label: str, timeout: float = 10) -> Json:
        """Wait for ``label`` and click it; returns the hit."""
        hit = self.wait_for(label, timeout)
        self.click(hit)
        return hit

    def scroll_to(self, hit: Json) -> None:
        """Wheel-scroll until ``hit`` (by its text) is inside the viewport."""
        for _ in range(30):
            now = self.find(hit["text"])
            if now is None or now["visible"]:
                return
            height = self.evaluate("innerHeight")
            dy = 300 if now["y"] > height else -300  # type: ignore[operator]
            self.page.call(
                "Input.dispatchMouseEvent",
                type="mouseWheel",
                x=now["x"] if 0 < now["x"] < 1200 else 400,
                y=300,
                deltaX=0,
                deltaY=dy,
            )
            self.page.pump(0.2)

    def wheel(self, x: float, y: float, dy: float) -> None:
        """One mouse-wheel scroll of ``dy`` px at (x, y)."""
        self.page.call(
            "Input.dispatchMouseEvent",
            type="mouseWheel",
            x=x,
            y=y,
            deltaX=0,
            deltaY=dy,
        )

    def find_scrolling(self, label: str, x: float, tries: int = 12) -> Json:
        """Wheel down the list under ``x`` until ``label`` is built and shown.

        ListView builds only rows near the viewport, so a row far below the
        fold has no semantics node until scrolled to.
        """
        for _ in range(tries):
            hit = self.find(label)
            # Wholly on screen, clear of the bottom edge (a sliver counts as
            # "visible" but a click there can miss).
            if hit and hit["visible"] and 40 < hit["y"] < 860:
                return hit
            self.wheel(x, 400, 300)
            self.page.pump(0.3)
        msg = f'"{label}" not found after scrolling'
        raise CdpError(msg)

    def long_press(self, x: float, y: float, hold: float = 0.9) -> None:
        """Press the left button at (x, y), hold ``hold`` s, release there
        (no move in between: that would trip the long-press slop check)."""
        point = {"x": x, "y": y}
        self.page.call("Input.dispatchMouseEvent", type="mouseMoved", **point)
        press = {"button": "left", "clickCount": 1, **point}
        self.page.call("Input.dispatchMouseEvent", type="mousePressed", **press)
        self.page.pump(hold)
        self.page.call("Input.dispatchMouseEvent", type="mouseReleased", **press)

    def key(self, key: str, code: int) -> None:
        """Press and release a non-text key, e.g. ``key("End", 35)``."""
        down = {"key": key, "code": key, "windowsVirtualKeyCode": code}
        self.page.call("Input.dispatchKeyEvent", type="rawKeyDown", **down)
        self.page.call("Input.dispatchKeyEvent", type="keyUp", **down)

    def insert_text(self, text: str) -> None:
        """Type ``text`` into the focused field (an IME commit)."""
        self.page.call("Input.insertText", text=text)

    def key_space(self) -> None:
        """Press and release Space (the rehearsal's "done" shortcut)."""
        key = {"key": " ", "code": "Space", "windowsVirtualKeyCode": 32}
        self.page.call("Input.dispatchKeyEvent", type="keyDown", text=" ", **key)
        self.page.call("Input.dispatchKeyEvent", type="keyUp", **key)

    def screenshot(self, out: Path) -> Path:
        """Save the viewport as PNG."""
        out.parent.mkdir(parents=True, exist_ok=True)
        data = self.page.call("Page.captureScreenshot", format="png")["data"]
        out.write_bytes(base64.b64decode(data))
        return out
