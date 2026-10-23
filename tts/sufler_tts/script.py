"""The slice of the Script JSON (DOCS-contract.md) the voice service reads."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

UNSPOKEN_KINDS = frozenset({"direction", "heading"})


@dataclass(frozen=True)
class Character:
    """A cast member: slug id and display name."""

    id: str
    name: str


@dataclass(frozen=True)
class Line:
    """One unit of rehearsal (speech block or single lyric line)."""

    index: int
    speakers: tuple[str, ...]
    text: str
    kind: str

    @property
    def is_spoken(self) -> bool:
        """Mirror of Dart `ScriptLine.isSpoken`."""
        return self.kind not in UNSPOKEN_KINDS and self.text != ""


@dataclass(frozen=True)
class Script:
    """A whole play: id, cast and lines in reading order."""

    id: str
    title: str
    characters: tuple[Character, ...]
    lines: tuple[Line, ...]


def _str(obj: dict[str, Any], key: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str):
        raise ValueError(f"{key!r} must be a string")
    return value


def _objects(obj: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = obj.get(key)
    if not isinstance(value, list) or not all(isinstance(v, dict) for v in value):
        raise ValueError(f"{key!r} must be a list of objects")
    return value


def _line(obj: dict[str, Any]) -> Line:
    index = obj.get("index")
    speakers = obj.get("speakers") or []
    if not isinstance(index, int) or not isinstance(speakers, list):
        raise ValueError("line needs an int 'index' and a list 'speakers'")
    if not all(isinstance(s, str) for s in speakers):
        raise ValueError("'speakers' must hold character ids")
    return Line(index, tuple(speakers), _str(obj, "text"), _str(obj, "kind"))


def parse_script(data: object) -> Script:
    """Validate and parse a Script JSON object; raises ValueError when malformed."""
    if not isinstance(data, dict):
        raise ValueError("script must be an object")
    characters = tuple(
        Character(_str(c, "id"), _str(c, "name")) for c in _objects(data, "characters")
    )
    lines = tuple(_line(raw) for raw in _objects(data, "lines"))
    if any(line.index != i for i, line in enumerate(lines)):
        raise ValueError("lines[i].index must equal i")
    return Script(_str(data, "id"), _str(data, "title"), characters, lines)
