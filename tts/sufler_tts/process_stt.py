"""Run the real transcriber in its own child process that exits when idle.

Same reasoning as `process_engine.py`: only ending the process hands the whole
GPU back to games. A separate child (not the Chatterbox one) lets each model
load and unload on its own clock, and keeps the server free of ctranslate2.
"""

from __future__ import annotations

import contextlib
import importlib
import multiprocessing as mp
import threading
from multiprocessing.connection import Connection
from multiprocessing.process import BaseProcess

import numpy as np

from sufler_tts.engine import Audio
from sufler_tts.idle import IDLE_SECONDS, IdleReaper
from sufler_tts.transcribe import Transcriber, Transcript

Request = tuple[bytes, str] | None


def _load(factory: str) -> Transcriber:
    module, _, attr = factory.partition(":")
    transcriber: Transcriber = getattr(importlib.import_module(module), attr)()
    return transcriber


def serve(conn: Connection, factory: str) -> None:
    """Child main loop: load the model, then answer requests until None."""
    try:
        transcriber = _load(factory)
    except Exception as exc:
        conn.send(("err", f"{type(exc).__name__}: {exc}"))
        return
    conn.send(("ok", None))
    while (request := conn.recv()) is not None:
        raw, language = request
        try:
            audio = np.frombuffer(raw, dtype=np.float32)
            conn.send(("ok", transcriber.transcribe(audio, language)))
        except Exception as exc:
            conn.send(("err", f"{type(exc).__name__}: {exc}"))
    transcriber.close()


class ProcessTranscriber:
    """A `Transcriber` proxy: lazy child start, unload after `idle_s` idle."""

    def __init__(
        self,
        factory: str,
        name: str,
        idle_s: float = IDLE_SECONDS,
        watch_every: float | None = 15.0,
    ) -> None:
        """`factory` is `module:callable` returning a Transcriber in the child."""
        self.factory = factory
        self._name = name
        self._lock = threading.Lock()
        self._proc: BaseProcess | None = None
        self._conn: Connection | None = None
        self.reaper = IdleReaper(idle_s, self.close)
        self._stop = threading.Event()
        if watch_every is not None:
            threading.Thread(
                target=self.reaper.watch, args=(self._stop, watch_every), daemon=True
            ).start()

    @property
    def name(self) -> str:
        """Model id, known without starting the child."""
        return self._name

    @property
    def loaded(self) -> bool:
        """Whether a child (and so the model) is alive."""
        return self._proc is not None and self._proc.is_alive()

    def _start(self) -> Connection:
        ctx = mp.get_context("spawn")  # fork + CUDA is unsafe
        parent, child = ctx.Pipe()
        proc = ctx.Process(target=serve, args=(child, self.factory), daemon=True)
        proc.start()
        child.close()
        status, payload = parent.recv()
        if status != "ok":
            proc.join(10)
            raise RuntimeError(f"transcriber failed to load: {payload!s}")
        self._proc, self._conn = proc, parent
        return parent

    def transcribe(self, audio: Audio, language: str) -> Transcript:
        """Forward one clip to the child, starting it if needed."""
        raw = np.ascontiguousarray(audio, dtype=np.float32).tobytes()
        with self._lock:
            conn = self._conn if self.loaded and self._conn else self._start()
            self.reaper.touch()
            conn.send((raw, language))
            status, payload = conn.recv()
            self.reaper.touch()
        if status != "ok" or not isinstance(payload, Transcript):
            raise RuntimeError(str(payload))
        return payload

    def close(self) -> None:
        """Stop the child; the next transcribe call starts a fresh one."""
        with self._lock:
            proc, conn = self._proc, self._conn
            self._proc = self._conn = None
            if conn is not None:
                with contextlib.suppress(OSError):  # child already gone
                    conn.send(None)
                conn.close()
            if proc is not None:
                proc.join(30)
                if proc.is_alive():
                    proc.kill()
                    proc.join()
