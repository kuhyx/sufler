"""Deterministic character -> voice assignment from Polish names.

Gender is guessed from the name (feminine `-a` forms, a keyword list); voices
are dealt round-robin within each gender pool in cast order, so distinct
characters get distinct voices until a pool runs out. No `hash()`: it is
salted per process and would reshuffle voices on every restart.
"""

from __future__ import annotations

from typing import Literal

from sufler_tts.script import Line, Script
from sufler_tts.voices import NARRATOR, is_voice, pool

Guess = Literal["female", "male", "ensemble"]

_ENSEMBLE = (
    "wszyscy", "wszystkie", "chór", "razem", "tłum", "zespół", "krasnale",
    "dzieci", "głosy",
)  # fmt: skip
_FEMALE = (
    "królowa", "macocha", "śmierć", "śnieżynk", "pani", "matka", "mama",
    "babcia", "babka", "córka", "siostra", "wróżka", "czarownica", "księżniczka",
    "dziewczyn", "kobieta", "ciotka", "żona", "panna", "noc", "mysz", "sowa",
)  # fmt: skip
_MALE = (
    "wilk", "lis", "król", "krasnal", "pan", "ojciec", "tata", "dziadek",
    "syn", "brat", "książę", "rycerz", "smok", "kot", "pies", "niedźwiedź",
)  # fmt: skip
# Male given names that end in -a, so the -a rule must not catch them.
_MALE_A = ("kuba", "barnaba", "kosma", "bonawentura", "jarema", "zawisza")


def _words(name: str) -> list[str]:
    return [w.strip(".,-") for w in name.lower().replace("-", " ").split()]


def guess_gender(name: str) -> Guess:
    """Guess a voice gender from a Polish character name."""
    words = _words(name)
    for keywords, guess in (
        (_ENSEMBLE, "ensemble"),
        (_FEMALE, "female"),
        (_MALE, "male"),
    ):
        if any(w.startswith(k) for w in words for k in keywords):
            return guess  # type: ignore[return-value]
    if any(w in _MALE_A for w in words):
        return "male"
    return "female" if any(w.endswith("a") for w in words) else "male"


def _cast(script: Script) -> list[tuple[str, str]]:
    """(id, name) for every character, then speakers missing from the cast."""
    cast = [(c.id, c.name) for c in script.characters]
    known = {cid for cid, _ in cast}
    for line in script.lines:
        for speaker in line.speakers:
            if speaker not in known:
                known.add(speaker)
                cast.append((speaker, speaker.replace("-", " ")))
    return cast


def assign_voices(script: Script, overrides: dict[str, str]) -> dict[str, str]:
    """Map every character id to a voice id; overrides win.

    Raises ValueError for an override naming an unknown voice. Overrides for
    characters not in the script are ignored (a stale client after an edit).
    """
    bad = sorted(v for v in overrides.values() if not is_voice(v))
    if bad:
        raise ValueError(f"unknown voice id(s): {', '.join(bad)}")
    dealt = {"female": 0, "male": 0}
    voices: dict[str, str] = {}
    for cid, name in _cast(script):
        guess = guess_gender(name)
        if guess == "ensemble":
            voices[cid] = NARRATOR
        else:
            ids = pool(guess)
            voices[cid] = ids[dealt[guess] % len(ids)]
            dealt[guess] += 1
        voices[cid] = overrides.get(cid, voices[cid])
    return voices


def voice_for_line(line: Line, voices: dict[str, str]) -> str:
    """Unattributed lines get the narrator; group lines the first speaker's voice."""
    return voices[line.speakers[0]] if line.speakers else NARRATOR
