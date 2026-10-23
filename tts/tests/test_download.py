"""Stdlib downloader against a local HTTP server that mimics HF's 302 + Range."""

from __future__ import annotations

import hashlib
import threading
from collections.abc import Iterator
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from sufler_tts import download

BODY = bytes(range(256)) * 40  # 10 KiB, every byte value present
SHA = hashlib.sha256(BODY).hexdigest()


@dataclass
class Server:
    """What the fake host serves and every request it saw."""

    base: str
    honour_range: bool = True
    body: bytes = BODY
    requests: list[tuple[str, str | None]] = field(default_factory=list)


def _handler(state: Server) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            state.requests.append((self.path, self.headers.get("Range")))
            if self.path.startswith("/resolve/"):  # HF answers resolve with a 302
                self.send_response(302)
                self.send_header("Location", "/cdn/" + self.path[len("/resolve/") :])
                self.end_headers()
                return
            self._serve(self.headers.get("Range"))

        def _serve(self, rng: str | None) -> None:
            body, start = state.body, 0
            if rng and state.honour_range:
                start = int(rng.removeprefix("bytes=").rstrip("-"))
                if start >= len(body):
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{len(body)}")
                    self.end_headers()
                    return
                self.send_response(206)
                end = len(body) - 1
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(body)}")
            else:
                self.send_response(200)
            self.send_header("Content-Length", str(len(body) - start))
            self.end_headers()
            self.wfile.write(body[start:])

        def log_message(self, *_args: object) -> None:
            pass

    return Handler


@pytest.fixture
def server() -> Iterator[Server]:
    state = Server(base="")
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), _handler(state))
    state.base = f"http://127.0.0.1:{httpd.server_address[1]}"
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield state
    httpd.shutdown()
    httpd.server_close()


def _url(server: Server) -> str:
    return f"{server.base}/resolve/rev/file.bin"


def _part(dest: Path) -> Path:
    return dest.with_name(dest.name + ".part")


def test_fresh_download_follows_redirect(server: Server, tmp_path: Path) -> None:
    dest = tmp_path / "sub" / "file.bin"
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY
    assert not _part(dest).exists()
    assert [p for p, _ in server.requests] == [
        "/resolve/rev/file.bin",
        "/cdn/rev/file.bin",
    ]


def test_verified_file_makes_no_request(server: Server, tmp_path: Path) -> None:
    dest = tmp_path / "file.bin"
    dest.write_bytes(BODY)
    assert not download.fetch(_url(server), dest, SHA)
    assert server.requests == []


def test_resumes_partial_download_across_redirect(
    server: Server, tmp_path: Path
) -> None:
    dest = tmp_path / "file.bin"
    _part(dest).write_bytes(BODY[:3000])
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY
    assert server.requests[-1] == ("/cdn/rev/file.bin", "bytes=3000-")


def test_server_ignoring_range_restarts_from_zero(
    server: Server, tmp_path: Path
) -> None:
    server.honour_range = False
    dest = tmp_path / "file.bin"
    _part(dest).write_bytes(b"x" * 3000)  # stale bytes that must not survive
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY


def test_complete_part_is_verified_and_renamed(server: Server, tmp_path: Path) -> None:
    dest = tmp_path / "file.bin"
    _part(dest).write_bytes(BODY)  # killed after the last byte, before rename
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY
    assert not _part(dest).exists()


def test_poisoned_full_part_is_redownloaded(server: Server, tmp_path: Path) -> None:
    dest = tmp_path / "file.bin"
    _part(dest).write_bytes(b"y" * len(BODY))  # right size, wrong bytes -> 416
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY


def test_checksum_mismatch_leaves_nothing_behind(
    server: Server, tmp_path: Path
) -> None:
    dest = tmp_path / "file.bin"
    with pytest.raises(download.ChecksumError):
        download.fetch(_url(server), dest, "0" * 64)
    assert not dest.exists()
    assert not _part(dest).exists()


def test_corrupt_existing_file_is_replaced(server: Server, tmp_path: Path) -> None:
    dest = tmp_path / "file.bin"
    dest.write_bytes(b"truncated")
    assert download.fetch(_url(server), dest, SHA)
    assert dest.read_bytes() == BODY
