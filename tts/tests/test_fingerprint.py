"""The pack manifest's `fingerprint` (DOCS-contract.md "Audio pack")."""

from __future__ import annotations

import hashlib
from typing import Any

import pytest

from sufler_tts.pack import script_fingerprint
from sufler_tts.script import parse_script

SCRIPT: dict[str, Any] = {
    "id": "x",
    "title": "T",
    "characters": [],
    "lines": [
        {"index": 0, "speakers": [], "text": "Scena 1", "kind": "heading"},
        {
            "index": 1,
            "speakers": ["a", "b"],
            "text": "Zażółć gęślą",
            "kind": "dialogue",
        },
        {"index": 2, "speakers": ["a"], "text": "", "kind": "direction"},
    ],
}
# The three rows by hand (tab-separated, newline-terminated); the digest is
# `printf` of exactly these bytes piped to `sha256sum`, outside the code under test.
HAND_ROWS = "0\theading\t\tScena 1\n1\tdialogue\ta,b\tZażółć gęślą\n2\tdirection\ta\t\n"
HAND_DIGEST = "f910bdbe41d87489d1766643fb80adc2d6eb506a322b06d533291b3c68c88fe7"


def test_fingerprint_is_sha256_of_the_hand_written_rows() -> None:
    assert hashlib.sha256(HAND_ROWS.encode()).hexdigest() == HAND_DIGEST
    assert script_fingerprint(parse_script(SCRIPT)) == HAND_DIGEST


def _script_with(index: int, key: str, value: object) -> dict[str, Any]:
    lines = [dict(line) for line in SCRIPT["lines"]]
    lines[index][key] = value
    return {**SCRIPT, "lines": lines}


@pytest.mark.parametrize(
    ("index", "key", "value"),
    [(1, "text", "inny"), (1, "kind", "song"), (2, "speakers", []), (0, "index", 5)],
)
def test_fingerprint_changes_with_any_field(
    index: int, key: str, value: object
) -> None:
    base = script_fingerprint(parse_script(SCRIPT))
    changed = _script_with(index, key, value)
    if key == "index":  # a wrong index is rejected by the parser itself
        with pytest.raises(ValueError, match="index"):
            parse_script(changed)
    else:
        assert script_fingerprint(parse_script(changed)) != base
