"""What the app asks the PC for one line: an explanation, a fresh voice clip.

One core for both doors: the HTTP endpoints (`POST /explain`,
`POST /render_line`) and the RTDB relay (`relay/worker.py`) take the same
JSON body and call the same method, so the phone and the desktop get the
same answer (DOCS-contract.md "Assistant").
"""

from __future__ import annotations

import json
import zipfile
from pathlib import Path
from typing import Protocol

from sufler_tts.assign import assign_voices, voice_for_line
from sufler_tts.assist_error import AssistError
from sufler_tts.cache import ClipCache
from sufler_tts.engine import Engine
from sufler_tts.explain import ExplainRequest, parse_explain_request
from sufler_tts.pack import pack_name
from sufler_tts.render import render_clip
from sufler_tts.script import Script, parse_script
from sufler_tts.textprep import clean_text
from sufler_tts.voices import get_voice, is_voice

__all__ = ["Assist", "AssistError", "Explainer", "pack_voices"]


class Explainer(Protocol):
    """Turns one explain request into Polish text (`explain.ClaudeExplainer`)."""

    def explain(self, request: ExplainRequest) -> str:
        """The explanation; raises AssistError when unavailable."""
        ...


def pack_voices(packs: Path, script_id: str) -> dict[str, str]:
    """The voice map of the finished pack for `script_id` ({} without one)."""
    try:
        with zipfile.ZipFile(packs / pack_name(script_id)) as z:
            voices = json.loads(z.read("manifest.json")).get("voices")
    except OSError, KeyError, ValueError, zipfile.BadZipFile:
        return {}
    if not isinstance(voices, dict):
        return {}
    return {k: v for k, v in voices.items() if isinstance(v, str) and is_voice(v)}


def _line_request(body: object) -> tuple[Script, int]:
    if not isinstance(body, dict):
        raise ValueError("body must be {script, index}")
    index = body.get("index")
    if not isinstance(index, int) or isinstance(index, bool):
        raise ValueError("'index' must be an int")
    script = parse_script(body.get("script"))
    if not 0 <= index < len(script.lines):
        raise ValueError(f"no line {index} in this script")
    return script, index


class Assist:
    """Explain and re-render, on the service's own engine and clip cache."""

    def __init__(
        self,
        engine: Engine,
        cache: ClipCache,
        packs: Path,
        explainer: Explainer | None,
    ) -> None:
        """`explainer` None: /explain answers 503."""
        self.engine = engine
        self.cache = cache
        self.packs = packs
        self.explainer = explainer

    def explain(self, body: object) -> str:
        """Polish explanation of the selection in `body` (see explain.py)."""
        try:
            request = parse_explain_request(body)
        except ValueError as exc:
            raise AssistError(400, str(exc)) from None
        if self.explainer is None:
            raise AssistError(503, "no explainer on this service")
        return self.explainer.explain(request)

    def render_line(self, body: object) -> bytes:
        """The Ogg clip of `body["script"]` line `body["index"]` as it is now.

        Same voice as the pack: the PC's finished pack for this script id
        decides each character's voice (overrides it was rendered with
        included), the default assignment covers anyone it lacks. Same cache
        key as a pack render, so the next pack reuses this clip.
        """
        try:
            script, index = _line_request(body)
            voices = {**assign_voices(script, {}), **pack_voices(self.packs, script.id)}
        except ValueError as exc:
            raise AssistError(400, str(exc)) from None
        line = script.lines[index]
        text = clean_text(line.text)
        if not line.is_spoken or not text:
            raise AssistError(400, f"line {index} has nothing to say")
        voice = get_voice(voice_for_line(line, voices))
        try:
            return render_clip(text, voice, self.engine, self.cache).read_bytes()
        except (RuntimeError, OSError) as exc:
            raise AssistError(500, f"{type(exc).__name__}: {exc}") from None
