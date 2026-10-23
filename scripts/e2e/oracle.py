"""Expected values for the E2E flows, computed from the stored script JSON.

Independent of the app's Dart code: re-derives the contract rules in
DOCS-contract.md (isSpoken, role ownership, Anki cue -> line pairs) so the UI
and the exported deck are checked against the data, not against themselves.
"""

from __future__ import annotations

import html
import re
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
    songs: list[str]  # every song title, in script order


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
        songs=titles,
    )


def owns(role: str, line: Json) -> bool:
    """lib/model/role.dart ``Role.owns`` for a stored role string
    (``character:<id>``, ``song:<id>``, ``group:<id>+<id>…``; empty group =
    the chorus, i.e. lines without speakers)."""
    kind, _, rid = role.partition(":")
    if kind == "song":
        return line.get("songId") == rid
    if kind == "group":
        members = rid.split("+") if rid else []
        if not members:
            return not line["speakers"]
        return all(m in line["speakers"] for m in members)
    return rid in line["speakers"]


def is_mine(line: Json, roles: set[str]) -> bool:
    """``isMine``: a spoken line owned by any of ``roles``."""
    return is_spoken(line) and any(owns(r, line) for r in roles)


# lib/rehearsal/groups.dart: ensemble headings, and those meaning everyone.
_ENSEMBLE = re.compile(
    r"^(wszyscy|wszystkie|razem|chór|chor|chórem|zespół|tłum|krasnale|"
    r"krasnoludki|krasnoludy)\b",
    re.IGNORECASE,
)
_EVERYONE = re.compile(
    r"^(wszyscy|wszystkie|razem|chór|chor|chórem|zespół|tłum)\b", re.IGNORECASE
)


def _plural_of(script: Json, char: Json) -> set[str]:
    """``_pluralOf``: "Śnieżynki" -> {"Śnieżynka 1", "Śnieżynka 2"} ids."""
    name = char["name"].strip()
    word = name.lower().split(" ")[0]
    if " " in name or len(word) < 6:
        return set()
    stem = word[:-2]
    return {
        o["id"]
        for o in script["characters"]
        if o["id"] != char["id"]
        and o["name"].lower().startswith(stem)
        and " " in o["name"].strip()
    }


def own_groups(script: Json, char_id: str) -> set[str]:
    """Group roles that picking ``char_id`` pre-ticks (``suggestedGroups``):
    ensembles it belongs to ("Wszyscy" = everyone), and speaker sets of >= 3
    non-ensemble characters that speak together >= 2 times and include it."""
    out: set[str] = set()
    ensembles: set[str] = set()
    for c in script["characters"]:
        plural = _plural_of(script, c)
        if not (_ENSEMBLE.match(c["name"].strip()) or len(plural) >= 2):
            continue
        ensembles.add(c["id"])
        everyone = bool(_EVERYONE.match(c["name"].strip()))
        if everyone or char_id in plural:
            out.add(f"character:{c['id']}")
    sets: dict[str, int] = {}
    for line in script["lines"]:
        ids = sorted(set(line["speakers"]) - ensembles)
        if is_spoken(line) and len(ids) >= 3:
            key = "+".join(ids)
            sets[key] = sets.get(key, 0) + 1
    out |= {f"group:{k}" for k, n in sets.items() if n >= 2 and char_id in k.split("+")}
    return out


def expected_cards(script: Json, roles: set[str]) -> list[tuple[str, str]]:
    """(cue text that the front must contain, exact back) per own line."""
    cards: list[tuple[str, str]] = []
    cue: Json | None = None
    for line in script["lines"]:
        if not is_spoken(line):
            continue
        if is_mine(line, roles):
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


def pick_scene(script: Json, roles: set[str]) -> ScenePick:
    """The scene whose first own line comes after the fewest partner lines (>= 1).

    At least one partner line is required: flow F3 must hear a partner first.
    """
    best: ScenePick | None = None
    for scene in script["scenes"]:
        lines = script["lines"][scene["start"] : scene["end"] + 1]
        cues = [ln for ln in lines if is_spoken(ln)]
        mine = [i for i, ln in enumerate(cues) if is_mine(ln, roles)]
        if not mine or mine[0] == 0:
            continue
        pick = ScenePick(
            scene["title"], scene["start"], scene["end"], len(cues), mine[0]
        )
        if best is None or pick.partner_before_mine < best.partner_before_mine:
            best = pick
    if best is None:
        msg = f"no scene with a line of {sorted(roles)} after a partner line"
        raise ValueError(msg)
    return best


def unescape(text: str) -> str:
    """Inverse of :func:`_html`, for readable failure messages."""
    return html.unescape(text.replace("<br>", "\n"))
