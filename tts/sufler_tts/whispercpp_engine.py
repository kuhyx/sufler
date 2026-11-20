"""whisper.cpp large-v3-turbo on the GPU through Vulkan. STT child only.

whisper.cpp (MIT) comes from the Arch packages `whisper-cpp` + `ggml-vulkan`
(scripts/install_tts.sh): no CUDA library and no pip wheel. The child keeps
one `whisper-server` with the model on the GPU; ending the child ends it.

Silence is cut here, not inside whisper-server: with its `--vad` the segment
times are mapped back to the clip but the word times are not (1.9.5). So
`whisper-vad-speech-segments` finds the speech spans first, each span is
transcribed on its own, and every time is shifted by its span start.
"""

from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
import uuid
import wave
from pathlib import Path
from typing import Any

import numpy as np

from sufler_tts.assets import WHISPERCPP_DIR
from sufler_tts.engine import Audio
from sufler_tts.transcribe import STT_RATE, Segment, Transcript, Word, whisper_name

SERVER = "whisper-server"
VAD = "whisper-vad-speech-segments"
MODEL_DIR = WHISPERCPP_DIR
MODEL_FILE = "ggml-large-v3-turbo.bin"
VAD_FILE = "ggml-silero-v5.1.2.bin"
PORT = 8792  # loopback; the service itself is on 8791
BEAM_SIZE = 2
# Lines are separated by short pauses: split at 500 ms of silence, pad 150 ms.
VAD_ARGS = ["-vsd", "500", "-vp", "150"]
LOAD_TIMEOUT_S = 60.0
REQUEST_TIMEOUT_S = 30.0
_SPAN = re.compile(r"Speech segment \d+: start = ([\d.]+), end = ([\d.]+)")
_DEVICE = re.compile(r"ggml_vulkan: (\d+) = (.+?) \(")
_USING = re.compile(r"using Vulkan(\d+) backend")


def _env(*, gpu: bool = True) -> dict[str, str]:
    """No MangoHud layer on a compute-only device; no GPU at all for the VAD.

    The VAD runs on the CPU either way; hiding the Vulkan driver from it skips
    device enumeration, 80 ms of every request.
    """
    env = {**os.environ, "DISABLE_MANGOHUD": "1"}
    return env if gpu else {**env, "VK_ICD_FILENAMES": os.devnull}


def _tied_to_parent() -> list[str]:
    """`setpriv --pdeathsig TERM`: whisper-server dies with the STT child."""
    setpriv = shutil.which("setpriv")  # util-linux
    return [setpriv, "--pdeathsig", "TERM"] if setpriv else []


def _tools() -> dict[str, str]:
    found = {name: shutil.which(name) for name in (SERVER, VAD)}
    missing = [name for name, path in found.items() if path is None]
    if missing:
        raise FileNotFoundError(
            f"{', '.join(missing)} not on PATH: run scripts/install_tts.sh "
            "(pacman whisper-cpp ggml-vulkan)"
        )
    return {name: path for name, path in found.items() if path}


def _wav(audio: Audio) -> bytes:
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(STT_RATE)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


def _multipart(fields: dict[str, str], wav: bytes) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'
        for k, v in fields.items()
    ]
    head = (
        f"--{boundary}\r\nContent-Disposition: form-data; "
        'name="file"; filename="clip.wav"\r\nContent-Type: audio/wav\r\n\r\n'
    )
    body = "".join(parts).encode() + head.encode() + wav
    return body + f"\r\n--{boundary}--\r\n".encode(), boundary


def parse(body: dict[str, Any], offset: float) -> tuple[list[Segment], list[Word]]:
    """verbose_json -> segments and whole words, shifted by `offset` seconds.

    whisper.cpp's `words` are BPE pieces: one with a leading space starts a
    word, the rest (punctuation too) extend it, as faster-whisper's words did.
    A segment that starts mid-word ("dus" | "zno.") is merged into the last.
    """
    segs: list[list[Any]] = []
    pieces: list[list[Any]] = []
    for seg in body.get("segments", []):
        text = seg["text"]
        if segs and text[:1] not in {" ", ""}:
            segs[-1][1], segs[-1][2] = seg["end"], segs[-1][2] + text
        else:
            segs.append([seg["start"], seg["end"], text])
        for w in seg.get("words", []):
            if w["word"].startswith("[_"):
                continue  # special tokens ([_BEG_], [_TT_n])
            if pieces and not w["word"].startswith(" "):
                pieces[-1][1], pieces[-1][2] = w["end"], pieces[-1][2] + w["word"]
            else:
                pieces.append([w["start"], w["end"], w["word"]])

    def at(t: float) -> float:
        return round(t + offset, 2)

    segments = [Segment(at(a), at(b), t.strip()) for a, b, t in segs if t.strip()]
    words = [Word(at(a), at(b), t.strip()) for a, b, t in pieces if t.strip()]
    return segments, words


class WhisperCppTranscriber:
    """Starts `whisper-server` with the model on construction; `close` ends it."""

    def __init__(self, port: int = PORT) -> None:
        """Check tools and model files, start the server, wait for its model."""
        tools = _tools()
        self._vad_bin = tools[VAD]
        model, vad = MODEL_DIR / MODEL_FILE, MODEL_DIR / VAD_FILE
        for path in (model, vad):
            if not path.is_file():
                raise FileNotFoundError(f"no {path}: run scripts/install_tts.sh")
        self._vad_model = vad
        self._url = f"http://127.0.0.1:{port}"
        self._tmp = Path(tempfile.mkdtemp(prefix="sufler-stt-"))
        self._log = self._tmp / "whisper-server.log"
        cmd = [
            *_tied_to_parent(),
            tools[SERVER],
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
        ]
        cmd += ["-m", str(model), "-bs", str(BEAM_SIZE), "-mc", "0"]
        with self._log.open("wb") as log:
            self.server = subprocess.Popen(
                cmd,
                stdout=log,
                stderr=subprocess.STDOUT,
                env=_env(),
            )
        try:
            self._wait_ready()
            self.device = self._device()
        except BaseException:
            self.close()
            raise

    def _log_text(self) -> str:
        return self._log.read_text(errors="replace")

    def _wait_ready(self) -> None:
        deadline = time.monotonic() + LOAD_TIMEOUT_S
        while time.monotonic() < deadline:
            if self.server.poll() is not None:
                tail = self._log_text().strip().splitlines()[-3:]
                raise RuntimeError(f"{SERVER} exited: {' | '.join(tail)}")
            try:
                with urllib.request.urlopen(f"{self._url}/health", timeout=1):
                    return
            except OSError:  # not listening yet, or 503 while loading
                time.sleep(0.05)
        raise RuntimeError(f"{SERVER} not ready after {LOAD_TIMEOUT_S:.0f} s")

    def _device(self) -> str:
        log = self._log_text()
        using = _USING.search(log)
        names = dict(_DEVICE.findall(log))
        if using is None or using[1] not in names:
            raise RuntimeError(f"{SERVER} found no Vulkan GPU (install ggml-vulkan)")
        return f"vulkan:{names[using[1]]}"

    @property
    def name(self) -> str:
        """`whisper.cpp@<ver>/large-v3-turbo`."""
        return whisper_name()

    def _spans(self, audio: Audio) -> list[tuple[float, float]]:
        clip = self._tmp / "clip.wav"
        clip.write_bytes(_wav(audio))
        cmd = [self._vad_bin, "-np", "-vm", str(self._vad_model), *VAD_ARGS]
        out = subprocess.run(
            [*cmd, "-f", str(clip)],
            capture_output=True,
            text=True,
            check=True,
            timeout=REQUEST_TIMEOUT_S,
            env=_env(gpu=False),
        )
        return [(float(a) / 100, float(b) / 100) for a, b in _SPAN.findall(out.stdout)]

    def _decode(self, audio: Audio, language: str) -> dict[str, Any]:
        fields = {"language": language, "response_format": "verbose_json"}
        body, boundary = _multipart(fields, _wav(audio))
        request = urllib.request.Request(f"{self._url}/inference", body)
        request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_S) as r:
            result: dict[str, Any] = json.loads(r.read())
        return result

    def transcribe(self, audio: Audio, language: str) -> Transcript:
        """Transcribe 16 kHz mono samples, one request per speech span."""
        segments: list[Segment] = []
        words: list[Word] = []
        for start, end in self._spans(audio):
            chunk = audio[int(start * STT_RATE) : int(end * STT_RATE)]
            segs, ws = parse(self._decode(chunk, language), start)
            segments += segs
            words += ws
        if not segments:
            return Transcript("", [], None, None, self.name)
        text = " ".join(s.text for s in segments)
        first = words[0].start if words else segments[0].start
        last = words[-1].end if words else segments[-1].end
        return Transcript(text, segments, first, last, self.name, words)

    def close(self) -> None:
        """Stop whisper-server (frees the GPU) and drop the scratch dir."""
        if self.server.poll() is None:
            self.server.terminate()
            try:
                self.server.wait(10)
            except subprocess.TimeoutExpired:
                self.server.kill()
                self.server.wait()
        shutil.rmtree(self._tmp, ignore_errors=True)
