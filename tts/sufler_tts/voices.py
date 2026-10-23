"""The voice bank: generated voices only, never a recording of a real person.

A voice is a timbre *base* plus Chatterbox generation params plus a DSP pitch
shift applied to the output. Bases are Chatterbox's built-in conditionals
(`default`) or a prompt that is itself synthetic Piper output (`piper-<name>`,
rendered by `assets.py`); no human recording ever enters the pipeline.
Distinctness is measured by `voicecheck.py`; retune `pitch` there, not here
by ear.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Literal

Gender = Literal["female", "male", "neutral"]
NARRATOR = "narrator"


@dataclass(frozen=True)
class Voice:
    """One entry of the bank. Every field feeds the clip cache key."""

    id: str
    label: str
    gender: Gender
    base: str
    pitch: float = 0.0  # semitones, rubberband with shifted formants
    exaggeration: float = 0.5
    cfg_weight: float = 0.5
    temperature: float = 0.8

    def spec(self) -> dict[str, object]:
        """Everything that changes the audio, for hashing."""
        return asdict(self)

    def public(self) -> dict[str, str]:
        """What GET /voices returns."""
        return {"id": self.id, "label": self.label, "gender": self.gender}


BANK: tuple[Voice, ...] = (
    # A pitch ladder ~2.6 semitones apart, 80-270 Hz. Base F0s measured
    # pre-DSP: darkman ~112, mc_speech ~117, default ~150, gosia ~205 Hz.
    Voice("m1", "Bas", "male", "piper-darkman", -5.8),
    Voice("m2", "Baryton", "male", "piper-darkman", -3.2),
    Voice("m3", "Tenor", "male", "piper-mc_speech", -1.3),
    Voice("m4", "Tenor jasny", "male", "piper-mc_speech", 1.4),
    Voice(NARRATOR, "Narrator", "neutral", "default", 0.0),
    Voice("f1", "Alt", "female", "piper-gosia", -3.0),
    Voice("f2", "Mezzosopran", "female", "piper-gosia", -0.5),
    Voice("f3", "Sopran", "female", "piper-gosia", 2.3),
    Voice("f4", "Sopran wysoki", "female", "piper-gosia", 4.9),
)
_BY_ID = {v.id: v for v in BANK}


def get_voice(voice_id: str) -> Voice:
    """Look up a voice; KeyError for an unknown id."""
    return _BY_ID[voice_id]


def is_voice(voice_id: str) -> bool:
    """Whether `voice_id` names a bank voice."""
    return voice_id in _BY_ID


def pool(gender: Gender) -> list[str]:
    """Voice ids of one gender, in bank order."""
    return [v.id for v in BANK if v.gender == gender]
