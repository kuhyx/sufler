"""Run the real engine in a child process that exits when idle.

Freeing a model in-process (`del` + `torch.cuda.empty_cache()`) leaves the
CUDA context resident (hundreds of MB). Ending the process is the only way
to hand the whole GPU back to games, so the server never imports torch.
"""

from __future__ import annotations

import contextlib
import importlib
import multiprocessing as mp
import threading
from multiprocessing.connection import Connection
from multiprocessing.process import BaseProcess

import numpy as np

from sufler_tts.engine import SAMPLE_RATE, Audio, Engine
from sufler_tts.idle import IDLE_SECONDS, IdleReaper
from sufler_tts.voices import Voice

Request = tuple[str, Voice, int] | None
Reply = tuple[str, bytes | str]


def _load(factory: str) -> Engine:
    module, _, attr = factory.partition(":")
    engine: Engine = getattr(importlib.import_module(module), attr)()
    return engine


def serve(conn: Connection, factory: str) -> None:
    """Child main loop: load the engine, then answer requests until None."""
    try:
        engine = _load(factory)
    except Exception as exc:
        conn.send(("err", f"{type(exc).__name__}: {exc}"))
        return
    conn.send(("ok", b""))
    while (request := conn.recv()) is not None:
        text, voice, seed = request
        try:
            audio = engine.synthesize(text, voice, seed)
            conn.send(("ok", np.asarray(audio, dtype=np.float32).tobytes()))
        except Exception as exc:
            conn.send(("err", f"{type(exc).__name__}: {exc}"))
    engine.close()


class ProcessEngine:
    """An `Engine` proxy: lazy child start, unload after `idle_s` without use."""

    def __init__(
        self,
        factory: str,
        name: str,
        idle_s: float = IDLE_SECONDS,
        watch_every: float | None = 15.0,
    ) -> None:
        """`factory` is `module:callable` returning an Engine inside the child."""
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
        """Engine id, known without starting the child."""
        return self._name

    @property
    def sample_rate(self) -> int:
        """Chatterbox renders at 24 kHz."""
        return SAMPLE_RATE

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
            raise RuntimeError(f"engine failed to load: {payload!s}")
        self._proc, self._conn = proc, parent
        return parent

    def synthesize(self, text: str, voice: Voice, seed: int) -> Audio:
        """Forward one chunk to the child, starting it if needed."""
        with self._lock:
            conn = self._conn if self.loaded and self._conn else self._start()
            self.reaper.touch()
            conn.send((text, voice, seed))
            status, payload = conn.recv()
            self.reaper.touch()
        if status != "ok" or not isinstance(payload, bytes):
            raise RuntimeError(str(payload))
        return np.frombuffer(payload, dtype=np.float32).copy()

    def close(self) -> None:
        """Stop the child; the next synthesize call starts a fresh one."""
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
