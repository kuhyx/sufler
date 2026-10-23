"""Expected values for the E2E flows, computed from the stored script JSON.

Independent of the app's Dart code: re-derives the contract rules in
DOCS-contract.md (isSpoken, role ownership, Anki cue -> line pairs) so the UI
and the exported deck are checked against the data, not against themselves.
"""

from __future__ import annotations

import html
from dataclasses import dataclass
from typing import Any

Json = dict[str, Any]


def is_spoken(line: Json) -> bool:
    """DOCS-contract: not a direction/heading, and text has a letter or digit."""
    if line["kind"] in {"direction", "heading"}:
        return False
    return any(ch.isalnum() for ch in line["text"])


def _html(text: str) -> str:
    """lib/anki/sufler_cards.dart `_html`: escape &, <, > and break lines."""
    escaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return escaped.replace("\n", "<br>")


@dataclass(frozen=True)
class RoleFacts:
    """What the UI and the deck must show for one character."""

    name: str
    spoken: list[Json]
    dialogue_blocks: int
    headed_songs: list[str]
    unheaded_songs: list[str]


def role_facts(script: Json, char_id: str) -> RoleFacts:
    """Spoken lines, dialogue blocks and the script's songs for ``char_id``."""
    name = next(c["name"] for c in script["characters"] if c["id"] == char_id)
    spoken = [
        ln for ln in script["lines"] if is_spoken(ln) and char_id in ln["speakers"]
    ]
    titles = [s["title"] for s in script["songs"]]
    return RoleFacts(
        name=name,
        spoken=spoken,
        dialogue_blocks=sum(1 for ln in spoken if ln["kind"] == "dialogue"),
        headed_songs=[t for t in titles if not t.startswith("♪ ")],
        unheaded_songs=[t for t in titles if t.startswith("♪ ")],
    )


def expected_cards(script: Json, char_id: str) -> list[tuple[str, str]]:
    """(cue text that the front must contain, exact back) per own line."""
    cards: list[tuple[str, str]] = []
    cue: Json | None = None
    for line in script["lines"]:
        if not is_spoken(line):
            continue
        if char_id in line["speakers"]:
            front = "(początek)" if cue is None else _html(cue["text"])
            cards.append((front, _html(line["text"])))
        cue = line
    return cards


@dataclass(frozen=True)
class ScenePick:
    """A scene to rehearse and where the first own line falls in it."""

    title: str
    start: int
    end: int
    cues: int
    partner_before_mine: int


def pick_scene(script: Json, char_id: str) -> ScenePick:
    """The scene whose first own line comes after the fewest partner lines (>= 1).

    At least one partner line is required: flow F3 must hear a partner first.
    """
    best: ScenePick | None = None
    for scene in script["scenes"]:
        lines = script["lines"][scene["start"] : scene["end"] + 1]
        cues = [ln for ln in lines if is_spoken(ln)]
        mine = [i for i, ln in enumerate(cues) if char_id in ln["speakers"]]
        if not mine or mine[0] == 0:
            continue
        pick = ScenePick(
            scene["title"], scene["start"], scene["end"], len(cues), mine[0]
        )
        if best is None or pick.partner_before_mine < best.partner_before_mine:
            best = pick
    if best is None:
        msg = f"no scene with a {char_id} line after a partner line"
        raise ValueError(msg)
    return best


def unescape(text: str) -> str:
    """Inverse of :func:`_html`, for readable failure messages."""
    return html.unescape(text.replace("<br>", "\n"))
