"""Text clean-up before synthesis, and splitting of long speech blocks.

Chatterbox caps one generation at ~40 s of speech, and quality drops on long
inputs, so blocks are cut at sentence boundaries and the clips concatenated.
"""

from __future__ import annotations

import re

# Bump when clean_text/split_text change output: it is part of the cache key.
TEXTPREP_VERSION = "1"
MAX_CHARS = 250

_INNER_PARENS = re.compile(r"\([^()]*\)")
_PAUSE = re.compile(r"/\s*\.\.\.\s*/")
_SENTENCE_END = re.compile(r"(?<=[.!?…])\s+")
_CLAUSE_END = re.compile(r"(?<=[,;:])\s+")


def clean_text(text: str) -> str:
    """Strip leftover `( … )` directions and `/.../` pauses; collapse whitespace."""
    previous = None
    while previous != text:  # innermost first, so nesting is handled
        previous, text = text, _INNER_PARENS.sub(" ", text)
    text = _PAUSE.sub(" ", text)
    return " ".join(text.split())


def _pack(pieces: list[str], max_chars: int) -> list[str]:
    """Greedily join consecutive pieces with spaces while they fit."""
    chunks: list[str] = []
    for piece in pieces:
        if chunks and len(chunks[-1]) + 1 + len(piece) <= max_chars:
            chunks[-1] = f"{chunks[-1]} {piece}"
        else:
            chunks.append(piece)
    return chunks


def _split_piece(piece: str, max_chars: int) -> list[str]:
    """Split one over-long sentence at clause marks, then at words."""
    if len(piece) <= max_chars:
        return [piece]
    clauses = _CLAUSE_END.split(piece)
    if len(clauses) > 1:
        parts = [p for c in clauses for p in _split_piece(c, max_chars)]
        return _pack(parts, max_chars)
    return _pack(piece.split(" "), max_chars)


def split_text(text: str, max_chars: int = MAX_CHARS) -> list[str]:
    """Cut cleaned text into chunks of at most `max_chars` (single words excepted).

    Joining the chunks with single spaces gives back the input.
    """
    sentences = _SENTENCE_END.split(text)
    pieces = [p for s in sentences for p in _split_piece(s, max_chars)]
    return _pack(pieces, max_chars)
