"""POST /explain: request parsing, the prompt, and the isolated `claude -p` call.

A fake `claude` (a tiny script) stands in for the real binary: no test ever
spends the subscription or reaches the network.
"""

from __future__ import annotations

import json
import stat
from pathlib import Path
from typing import Any

import pytest

from sufler_tts.assist import AssistError
from sufler_tts.explain import (
    ClaudeExplainer,
    build_prompt,
    parse_explain_request,
)


def _body(**over: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "scriptId": "abc123",
        "title": "Próba",
        "selection": "wilku",
        "line": {"index": 3, "speakers": ["Królowa"], "text": "Witaj, wilku!"},
        "before": [{"speakers": ["Piaskowy Wilk"], "text": "Dzień dobry."}],
        "after": [{"speakers": [], "text": "La la la."}],
    }
    body.update(over)
    return body


def test_parse_keeps_context_and_caps_it() -> None:
    before = [{"speakers": ["A"], "text": f"b{i}"} for i in range(5)]
    after = [{"speakers": ["B"], "text": f"a{i}"} for i in range(3)]
    req = parse_explain_request(_body(before=before, after=after))
    assert req.selection == "wilku"
    assert req.line.speakers == ("Królowa",)
    assert [c.text for c in req.before] == ["b2", "b3", "b4"]  # nearest 3
    assert [c.text for c in req.after] == ["a0"]  # nearest 1


def test_parse_accepts_missing_optional_context() -> None:
    body = _body()
    del body["before"], body["after"], body["title"], body["scriptId"]
    body["line"] = {"text": "Witaj, wilku!"}  # RTDB drops empty lists
    req = parse_explain_request(body)
    assert req.before == () and req.after == () and req.line.speakers == ()


@pytest.mark.parametrize(
    "body",
    [
        [],
        _body(selection=""),
        _body(selection="   "),
        _body(selection="x" * 1001),
        _body(line="Witaj"),
        _body(line={"speakers": ["A"]}),
        _body(before="nope"),
        _body(line={"text": "x", "speakers": [1]}),
    ],
)
def test_parse_rejects_malformed(body: object) -> None:
    with pytest.raises(ValueError):
        parse_explain_request(body)


def test_prompt_is_polish_and_carries_the_context() -> None:
    system, user = build_prompt(parse_explain_request(_body()))
    assert "po polsku" in system
    for part in ("„wilku”", "Królowa: Witaj, wilku!", "Piaskowy Wilk: Dzień"):
        assert part in user
    assert "(bez mówiącego): La la la." in user
    assert "150" in user and "mnemotechnik" in user
    assert "$" not in user  # every placeholder filled


def _fake_claude(tmp_path: Path, reply: object, code: int = 0) -> Path:
    """A `claude` stand-in that records argv, cwd and stdin, then replies."""
    log = tmp_path / "call.json"
    script = tmp_path / "claude"
    out = json.dumps(reply)
    script.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        f"open({str(log)!r}, 'w').write(json.dumps("
        "{'argv': sys.argv[1:], 'cwd': os.getcwd(), 'stdin': sys.stdin.read()}))\n"
        f"print({out!r})\n"
        f"sys.exit({code})\n"
    )
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return script


@pytest.mark.parametrize("as_list", [False, True])
def test_claude_call_is_isolated_and_returns_the_text(
    tmp_path: Path, as_list: bool
) -> None:
    reply: object = {"type": "result", "is_error": False, "result": "  Znaczy: ...  "}
    if as_list:  # newer CLIs print every event as one JSON array
        reply = [{"type": "system", "subtype": "init"}, reply]
    explainer = ClaudeExplainer(_fake_claude(tmp_path, reply))
    assert explainer.explain(parse_explain_request(_body())) == "Znaczy: ..."
    call = json.loads((tmp_path / "call.json").read_text())
    argv = call["argv"]
    assert argv[0] == "-p"
    assert argv[argv.index("--model") + 1] == "sonnet"
    assert argv[argv.index("--setting-sources") + 1] == ""
    assert argv[argv.index("--tools") + 1] == ""
    assert {"--strict-mcp-config", "--no-session-persistence"} <= set(argv)
    assert call["cwd"] == "/"  # no project CLAUDE.md to discover
    assert "„wilku”" in call["stdin"]


@pytest.mark.parametrize(
    ("reply", "code"),
    [
        ({"type": "result", "is_error": True, "result": "You've hit your limit"}, 1),
        ({"type": "result", "is_error": False, "result": "   "}, 0),
        ("not an object", 0),
        ([{"type": "system"}], 0),
    ],
)
def test_claude_failure_is_unavailable(
    tmp_path: Path, reply: object, code: int
) -> None:
    explainer = ClaudeExplainer(_fake_claude(tmp_path, reply, code))
    with pytest.raises(AssistError) as err:
        explainer.explain(parse_explain_request(_body()))
    assert err.value.status == 503


def test_claude_missing_or_slow_is_unavailable(tmp_path: Path) -> None:
    with pytest.raises(AssistError) as err:
        ClaudeExplainer(tmp_path / "nope").explain(parse_explain_request(_body()))
    assert err.value.status == 503
    slow = tmp_path / "slow"
    slow.write_text("#!/bin/sh\nsleep 5\n")
    slow.chmod(0o755)
    with pytest.raises(AssistError) as err:
        ClaudeExplainer(slow, timeout=0.2).explain(parse_explain_request(_body()))
    assert err.value.status == 503
    assert "timed out" in err.value.message


def test_default_binary_and_timeout() -> None:
    explainer = ClaudeExplainer()
    assert explainer.binary == Path.home() / ".local/bin/claude"
    assert explainer.timeout == 90.0
