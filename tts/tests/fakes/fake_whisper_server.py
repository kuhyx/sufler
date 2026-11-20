"""Stand-in for `whisper-server` (whisper.cpp): canned verbose_json, no model.

Logs to stderr what the real one logs about its Vulkan device, answers
GET /health and POST /inference, and records each inference body's form
fields in $FAKE_WHISPER_LOG. $FAKE_WHISPER_MODE: `ok` (default), `crash`
(exit before listening), `cpu` (no Vulkan device in the log).
"""

from __future__ import annotations

import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FIXTURE = Path(__file__).parent.parent / "fixtures" / "whispercpp_verbose.json"
MODE = os.environ.get("FAKE_WHISPER_MODE", "ok")
LOG = Path(os.environ.get("FAKE_WHISPER_LOG", os.devnull))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        del format, args

    def _send(self, body: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        self._send(b'{"status":"ok"}')

    def do_POST(self) -> None:
        raw = self.rfile.read(int(self.headers["Content-Length"]))
        fields = dict(re.findall(rb'name="(\w+)"\r\n\r\n([^\r]*)\r\n', raw))
        wav = raw.split(b"\r\n\r\n", len(fields) + 1)[-1]
        record = {k.decode(): v.decode() for k, v in fields.items()}
        record["riff"] = wav.startswith(b"RIFF")
        with LOG.open("a") as f:
            f.write(json.dumps(record) + "\n")
        self._send(FIXTURE.read_bytes())


def main() -> None:
    args = sys.argv[1:]
    print("ggml_vulkan: Found 1 Vulkan devices:", file=sys.stderr)
    if MODE == "crash":
        print("error: failed to open model", file=sys.stderr)
        sys.exit(1)
    if MODE != "cpu":
        print("ggml_vulkan: 0 = Fake GPU 3090 (NVIDIA) | uma: 0", file=sys.stderr)
        print("whisper_backend_init_gpu: using Vulkan0 backend", file=sys.stderr)
    sys.stderr.flush()
    port = int(args[args.index("--port") + 1])
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
