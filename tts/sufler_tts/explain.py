"""`POST /explain`: one isolated, headless `claude -p` call per selection.

Uses the logged-in `claude` CLI (kuhy's subscription; no API key on this
machine), isolated the way book-guard's grader is (`book_guard/_claude.py`):

* `--setting-sources ""`: none of `~/.claude/settings.json`'s hooks run (the
  status-tag Stop hook would otherwise send the answer back for a tag);
* `--tools ""` + `--strict-mcp-config`: the model reads and calls nothing;
* `cwd=/`: no project `CLAUDE.md` to discover.

The prompt lives in `explain_prompt.txt` (system part, `---USER---`, user
template with `$placeholders`).
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from string import Template
from typing import Any, Final

from sufler_tts.assist_error import AssistError

CLAUDE_BIN: Final = Path.home() / ".local/bin/claude"
"""Absolute: the systemd user unit has no shell PATH (`SUFLER_CLAUDE_BIN` wins)."""
MODEL: Final = "sonnet"
TIMEOUT_S: Final = 90.0
MAX_SELECTION: Final = 1000
MAX_TEXT: Final = 5000
BEFORE, AFTER = 3, 1
PROMPT_FILE: Final = Path(__file__).with_name("explain_prompt.txt")
_SPLIT: Final = "---USER---"


@dataclass(frozen=True)
class ContextLine:
    """One line of the play: who says it (display names) and what."""

    speakers: tuple[str, ...]
    text: str

    def render(self) -> str:
        """`Name, Name: text`, or `(bez mówiącego): text` for a chorus line."""
        who = ", ".join(self.speakers) or "(bez mówiącego)"
        return f"{who}: {self.text}"


@dataclass(frozen=True)
class ExplainRequest:
    """The selection, its line and the nearby lines (DOCS-contract.md)."""

    title: str
    selection: str
    line: ContextLine
    before: tuple[ContextLine, ...]
    after: tuple[ContextLine, ...]


def _context_line(raw: object) -> ContextLine:
    if not isinstance(raw, dict):
        raise ValueError("a context line must be {speakers, text}")
    text, speakers = raw.get("text"), raw.get("speakers") or []
    if not isinstance(text, str) or len(text) > MAX_TEXT:
        raise ValueError(f"line 'text' must be a string of <= {MAX_TEXT} chars")
    if not isinstance(speakers, list) or not all(isinstance(s, str) for s in speakers):
        raise ValueError("'speakers' must be a list of names")
    return ContextLine(tuple(speakers), text)


def _context(body: dict[str, Any], key: str) -> list[ContextLine]:
    raw = body.get(key) or []
    if not isinstance(raw, list):
        raise ValueError(f"{key!r} must be a list of lines")
    return [_context_line(r) for r in raw]


def parse_explain_request(body: object) -> ExplainRequest:
    """Validate a POST /explain body; ValueError when malformed.

    Missing `before`/`after`/`speakers`/`title` are fine (RTDB drops empty
    lists); extra context is cut to the nearest 3 lines before, 1 after.
    """
    if not isinstance(body, dict):
        raise ValueError("body must be an object")
    selection = body.get("selection")
    if not isinstance(selection, str) or not selection.strip():
        raise ValueError("'selection' must be non-empty text")
    if len(selection) > MAX_SELECTION:
        raise ValueError(f"'selection' is over {MAX_SELECTION} chars")
    title = body.get("title")
    return ExplainRequest(
        title=title if isinstance(title, str) else "",
        selection=selection.strip(),
        line=_context_line(body.get("line")),
        before=tuple(_context(body, "before")[-BEFORE:]),
        after=tuple(_context(body, "after")[:AFTER]),
    )


def build_prompt(request: ExplainRequest) -> tuple[str, str]:
    """(system prompt, user message) from `explain_prompt.txt`."""
    system, _, user = PROMPT_FILE.read_text(encoding="utf-8").partition(_SPLIT)

    def lines(ctx: tuple[ContextLine, ...]) -> str:
        return "\n".join(c.render() for c in ctx) or "(brak)"

    filled = Template(user.strip()).substitute(
        title=request.title or "bez tytułu",
        before=lines(request.before),
        line=request.line.render(),
        after=lines(request.after),
        selection=request.selection,
    )
    return system.strip(), filled


class ClaudeExplainer:
    """Runs the CLI; every failure is an AssistError 503 with the reason."""

    def __init__(self, binary: Path | None = None, timeout: float = TIMEOUT_S) -> None:
        """`binary` defaults to `$SUFLER_CLAUDE_BIN`, else `~/.local/bin/claude`."""
        env = os.environ.get("SUFLER_CLAUDE_BIN")
        self.binary = binary or (Path(env) if env else CLAUDE_BIN)
        self.timeout = timeout

    def command(self, system: str) -> list[str]:
        """The isolated `claude -p` argv (the message goes on stdin)."""
        return [
            str(self.binary), "-p", "--output-format", "json",
            "--setting-sources", "", "--tools", "", "--strict-mcp-config",
            "--no-session-persistence", "--model", MODEL, "--system-prompt", system,
        ]  # fmt: skip

    def explain(self, request: ExplainRequest) -> str:
        """The model's answer text, stripped."""
        system, user = build_prompt(request)
        try:
            done = subprocess.run(
                self.command(system),
                input=user,
                capture_output=True,
                text=True,
                cwd="/",
                env={**os.environ, "MAX_THINKING_TOKENS": "1024"},
                timeout=self.timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            raise AssistError(
                503, f"claude timed out after {self.timeout:g} s"
            ) from None
        except OSError as exc:
            raise AssistError(503, f"claude could not run: {exc}") from None
        return _answer(done.stdout, done.returncode)


def _answer(stdout: str, code: int) -> str:
    try:
        reply = json.loads(stdout, strict=False)
    except ValueError:
        reply = None
    if isinstance(reply, list):  # CLI 2.1.3xx: every event, the result last
        results = [
            e for e in reply if isinstance(e, dict) and e.get("type") == "result"
        ]
        reply = results[-1] if results else None
    if not isinstance(reply, dict):
        raise AssistError(503, f"claude exited {code} without a result")
    text = str(reply.get("result") or "").strip()
    if code != 0 or reply.get("is_error") or not text:
        raise AssistError(503, f"claude failed: {text[:300] or f'exit {code}'}")
    return text
