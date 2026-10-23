"""Render jobs: one worker thread, because there is one GPU."""

from __future__ import annotations

import queue
import re
import threading
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from sufler_tts.assign import assign_voices
from sufler_tts.cache import ClipCache
from sufler_tts.engine import Engine
from sufler_tts.pack import pack_name
from sufler_tts.render import render_script
from sufler_tts.script import Script, parse_script

State = Literal["queued", "running", "done", "error"]
_SAFE_ID = re.compile(r"[A-Za-z0-9_-]{1,128}")


@dataclass
class Job:
    """Progress of one render request."""

    id: str
    script_id: str
    total: int = 0
    done: int = 0
    state: State = "queued"
    error: str | None = None

    def public(self) -> dict[str, object]:
        """What GET /jobs/<id> returns."""
        body: dict[str, object] = {
            "done": self.done,
            "total": self.total,
            "state": self.state,
        }
        if self.error is not None:
            body["error"] = self.error
        return body


class JobRunner:
    """Validates requests up front, renders them one at a time in order."""

    def __init__(self, engine: Engine, cache: ClipCache, packs: Path) -> None:
        """Start the worker thread."""
        self.engine = engine
        self.cache = cache
        self.packs = packs
        self._jobs: dict[str, Job] = {}
        self._queue: queue.Queue[tuple[Job, Script, dict[str, str]] | None] = (
            queue.Queue()
        )
        self._worker = threading.Thread(target=self._work, daemon=True)
        self._worker.start()

    def submit(self, script_json: object, overrides: object) -> Job:
        """Queue a render; ValueError for a malformed script or override."""
        script = parse_script(script_json)
        if not _SAFE_ID.fullmatch(script.id):
            raise ValueError("script id must be [A-Za-z0-9_-]{1,128}")
        if not isinstance(overrides, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in overrides.items()
        ):
            raise ValueError("'voices' must map character ids to voice ids")
        assign_voices(script, overrides)  # rejects unknown voice ids now
        job = Job(uuid.uuid4().hex, script.id)
        self._jobs[job.id] = job
        self._queue.put((job, script, overrides))
        return job

    def job(self, job_id: str) -> Job | None:
        """A job by id."""
        return self._jobs.get(job_id)

    def pack(self, script_id: str) -> Path | None:
        """The finished pack for a script, if one exists."""
        if not _SAFE_ID.fullmatch(script_id):
            return None
        path = self.packs / pack_name(script_id)
        return path if path.is_file() else None

    def stop(self) -> None:
        """Finish queued jobs, then stop the worker and release the engine."""
        self._queue.put(None)
        self._worker.join()
        self.engine.close()

    def _work(self) -> None:
        while (item := self._queue.get()) is not None:
            job, script, overrides = item
            job.state = "running"

            def progress(done: int, total: int, job: Job = job) -> None:
                job.done, job.total = done, total

            try:
                render_script(
                    script, overrides, self.engine, self.cache, self.packs, progress
                )
            except Exception as exc:
                job.state, job.error = "error", f"{type(exc).__name__}: {exc}"
            else:
                job.state = "done"
