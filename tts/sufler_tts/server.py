"""Loopback-only HTTP API (stdlib: no web framework to pin and keep fresh).

GET  /health            {ok, engine, gpu}
GET  /voices            [{id, label, gender}]
POST /render[?voices=c:v,...]  bare Script JSON -> {jobId}
GET  /jobs/<id>         {done, total, state[, error]}
GET  /packs/<id>.zip    the audio pack (DOCS-contract.md)
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from collections.abc import Callable
from functools import cache
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

from sufler_tts.jobs import JobRunner
from sufler_tts.pack import pack_name
from sufler_tts.voices import BANK

HOST = "127.0.0.1"
PORT = 8791
MAX_BODY = 32 * 1024 * 1024
_JOB = re.compile(r"/jobs/([0-9a-f]{32})")
_PACK = re.compile(r"/packs/([^/]+)\.zip")


@cache
def gpu_name() -> str | None:
    """The GPU model per nvidia-smi (no torch in the server process)."""
    if shutil.which("nvidia-smi") is None:
        return None
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    return out.stdout.strip().splitlines()[0] if out.returncode == 0 else None


def parse_render_request(body: object, query: str) -> tuple[object, object]:
    """(script, voice overrides) from a POST /render.

    The app sends the bare `Script.toJson()` (lib/tts/render_client.dart);
    overrides ride in `?voices=<charId>:<voiceId>,...`. A wrapped
    `{"script": ..., "voices": {...}}` body is accepted too.
    """
    if not isinstance(body, dict):
        raise ValueError("body must be a Script object")
    wrapped = "script" in body
    script = body["script"] if wrapped else body
    voices = body.get("voices") or {} if wrapped else {}
    if not isinstance(voices, dict):
        raise ValueError("'voices' must map character ids to voice ids")
    for value in parse_qs(query).get("voices", []):
        for item in filter(None, value.split(",")):
            char_id, sep, voice_id = item.partition(":")
            if not sep or not char_id or not voice_id:
                raise ValueError("voices must be <characterId>:<voiceId>,...")
            voices[char_id] = voice_id
    return script, voices


def _handler(
    runner: JobRunner, gpu: Callable[[], str | None]
) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            del format, args  # quiet: journald gets only errors

        def _json(self, status: int, body: object) -> None:
            data = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _not_found(self) -> None:
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

        def do_GET(self) -> None:
            path = self.path.split("?", 1)[0]
            if path == "/health":
                body = {"ok": True, "engine": runner.engine.name, "gpu": gpu()}
                self._json(HTTPStatus.OK, body)
            elif path == "/voices":
                self._json(HTTPStatus.OK, [v.public() for v in BANK])
            elif (m := _JOB.fullmatch(path)) and (job := runner.job(m[1])):
                self._json(HTTPStatus.OK, job.public())
            elif (m := _PACK.fullmatch(path)) and (pack := runner.pack(m[1])):
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(pack.stat().st_size))
                disposition = f'attachment; filename="{pack_name(m[1])}"'
                self.send_header("Content-Disposition", disposition)
                self.end_headers()
                with pack.open("rb") as f:
                    shutil.copyfileobj(f, self.wfile)
            else:
                self._not_found()

        def do_POST(self) -> None:
            path, _, query = self.path.partition("?")
            if path != "/render":
                self._not_found()
                return
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_BODY:
                self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "too big"})
                return
            try:
                script, voices = parse_render_request(
                    json.loads(self.rfile.read(length)), query
                )
                job = runner.submit(script, voices)
            except ValueError as exc:  # JSONDecodeError is a ValueError
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            # 200, not 202: the Dart RenderClient accepts exactly 200.
            self._json(HTTPStatus.OK, {"jobId": job.id})

    return Handler


def make_server(
    runner: JobRunner,
    port: int = PORT,
    gpu: Callable[[], str | None] = gpu_name,
) -> ThreadingHTTPServer:
    """A server bound to 127.0.0.1 only; call `serve_forever()` on it."""
    server = ThreadingHTTPServer((HOST, port), _handler(runner, gpu))
    server.daemon_threads = True
    return server
