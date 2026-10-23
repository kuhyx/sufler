"""Resume-safe, sha256-verified HTTP downloads with nothing but the stdlib.

`fetch(url, dest, sha256)` leaves either the verified file at `dest` or no
`dest` at all: bytes accumulate in `<dest>.part` (resumed with an HTTP Range
request after an interrupted run) and only a verified `.part` is renamed into
place. A `dest` that already verifies costs zero requests, so re-running an
install is cheap.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import urllib.error
import urllib.request
from pathlib import Path

CHUNK = 1 << 20
TIMEOUT_S = 50.0


class ChecksumError(ValueError):
    """The downloaded bytes do not match the pinned sha256."""


def sha256_of(path: Path) -> str:
    """Hex sha256 of a file, read in 1 MiB chunks (weights are GBs)."""
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def _part(dest: Path) -> Path:
    return dest.with_name(dest.name + ".part")


def _range_start(content_range: str | None) -> int:
    """First byte of a `bytes <start>-<end>/<size>` header; -1 if unparseable."""
    try:
        return int((content_range or "").split()[1].split("-")[0])
    except IndexError, ValueError:
        return -1


def _transfer(url: str, part: Path, timeout: float) -> None:
    """Append the rest of `url` to `part`, or rewrite it when resume is refused."""
    offset = part.stat().st_size if part.is_file() else 0
    request = urllib.request.Request(url)
    if offset:
        # urllib keeps non-content headers across HF's 302 to the CDN.
        request.add_header("Range", f"bytes={offset}-")
    try:
        response = urllib.request.urlopen(request, timeout=timeout)
    except urllib.error.HTTPError as err:
        if err.code == 416:
            return
        raise
    with response:
        resumed = (
            response.status == 206
            and _range_start(response.headers.get("Content-Range")) == offset
        )
        with part.open("ab" if resumed else "wb") as f:
            shutil.copyfileobj(response, f, CHUNK)
            f.flush()
            os.fsync(f.fileno())


def fetch(url: str, dest: Path, sha256: str, *, timeout: float = TIMEOUT_S) -> bool:
    """Make `dest` hold the file with `sha256`; True when bytes were downloaded.

    A partial `.part` is resumed once; if the result does not verify (a stale
    or foreign `.part`), it is discarded and the file fetched from zero. A
    mismatch on a clean download raises `ChecksumError` and leaves no file.
    """
    if dest.is_file():
        if sha256_of(dest) == sha256:
            return False
        dest.unlink()
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = _part(dest)
    resumed = part.is_file()
    for _ in range(2 if resumed else 1):
        _transfer(url, part, timeout)
        if sha256_of(part) == sha256:
            part.replace(dest)  # atomic: same directory
            return True
        part.unlink()
    raise ChecksumError(f"{url}: sha256 mismatch (expected {sha256})")
