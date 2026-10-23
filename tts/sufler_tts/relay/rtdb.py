"""A minimal blocking RTDB REST client under `/sufler`: GET/PUT/DELETE + SSE.

Stdlib only (the service pins no web stack). Every call carries
`?auth=<idToken>` (RTDB REST has no header form), so no URL and no urllib
error text ever reaches a message or a log line: errors name the method,
the path and the status only (tutor's `relay/rtdb.py` rule).
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable, Iterator
from typing import Any, Final, Protocol

ROOT: Final = "sufler"
SERVER_TIME: Final = {".sv": "timestamp"}
TIMEOUT_S: Final = 30.0
# RTDB sends a keep-alive every 30 s; silence past this means a dead stream.
STREAM_TIMEOUT_S: Final = 75.0

Opener = Callable[..., Any]


class RtdbError(RuntimeError):
    """A request failed; the message never contains the URL or the token."""


class Db(Protocol):
    """What the relay worker needs (tests use an in-memory fake)."""

    def get(self, path: str, *, shallow: bool = False) -> Any:
        """The value at `path`, None when absent."""
        ...

    def put(self, path: str, value: object) -> Any:
        """Write `value`; returns it as stored (server times resolved)."""
        ...

    def delete(self, path: str) -> None:
        """Remove `path`."""
        ...


def parse_sse(lines: Iterable[str]) -> Iterator[tuple[str, object]]:
    """(event, decoded data) per Server-Sent Event; non-JSON data stays text."""
    event, data = "", ""
    for raw in lines:
        line = raw.rstrip("\r\n")
        if line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data = line[5:].strip()
        elif not line and event:
            try:
                value: object = json.loads(data)
            except ValueError:
                value = data
            yield event, value
            event, data = "", ""


class Rtdb:
    """REST calls relative to `<database_url>/sufler`."""

    def __init__(
        self,
        database_url: str,
        token: Callable[[], str],
        opener: Opener = urllib.request.urlopen,
    ) -> None:
        """`token` yields a fresh id token; `opener` is injectable for tests."""
        self._base = database_url.rstrip("/")
        self._token = token
        self._open = opener

    def _url(self, path: str, query: dict[str, str]) -> str:
        rel = "/".join(urllib.parse.quote(p, safe="") for p in path.split("/") if p)
        params = urllib.parse.urlencode({"auth": self._token(), **query})
        return f"{self._base}/{ROOT}/{rel}.json?{params}"

    def _call(
        self,
        method: str,
        path: str,
        *,
        value: object = None,
        query: dict[str, str] | None = None,
        stream: bool = False,
    ) -> Any:
        data = json.dumps(value).encode() if method == "PUT" else None
        request = urllib.request.Request(
            self._url(path, query or {}), data=data, method=method
        )
        if stream:
            request.add_header("Accept", "text/event-stream")
        timeout = STREAM_TIMEOUT_S if stream else TIMEOUT_S
        try:
            return self._open(request, timeout=timeout)
        except urllib.error.HTTPError as err:
            raise RtdbError(f"{method} {path}: HTTP {err.code}") from None
        except (OSError, ValueError) as err:  # URLError, timeouts, bad URL
            raise RtdbError(f"{method} {path}: {type(err).__name__}") from None

    def _json(self, method: str, path: str, **kwargs: Any) -> Any:
        response = self._call(method, path, **kwargs)
        try:
            with response:
                body = response.read()
        except OSError as err:
            raise RtdbError(f"{method} {path}: {type(err).__name__}") from None
        return json.loads(body) if body else None

    def get(self, path: str, *, shallow: bool = False) -> Any:
        """The value at `path` (`shallow`: its keys only, values `true`)."""
        query = {"shallow": "true"} if shallow else {}
        return self._json("GET", path, query=query)

    def put(self, path: str, value: object) -> Any:
        """Write `value`; the stored value comes back."""
        return self._json("PUT", path, value=value)

    def delete(self, path: str) -> None:
        """Remove `path` (absent is fine)."""
        self._json("DELETE", path)

    def stream(self, path: str) -> Iterator[tuple[str, object]]:
        """SSE events of one connection to `path` until it drops."""
        response = self._call("GET", path, stream=True)
        try:
            with response:
                lines = (raw.decode("utf-8", "replace") for raw in response)
                yield from parse_sse(lines)
        except OSError as err:  # read timeout, reset
            raise RtdbError(f"STREAM {path}: {type(err).__name__}") from None
