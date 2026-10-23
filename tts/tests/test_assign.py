"""Deterministic voice assignment from Polish character names."""

from __future__ import annotations

from typing import Any

import pytest

from sufler_tts.assign import assign_voices, guess_gender, voice_for_line
from sufler_tts.script import parse_script
from sufler_tts.voices import BANK, NARRATOR, get_voice


@pytest.mark.parametrize(
    ("name", "gender"),
    [
        ("Królowa", "female"),
        ("Zła Macocha", "female"),
        ("Śmierć", "female"),
        ("Śnieżynki", "female"),
        ("Pani Anna", "female"),
        ("Babcia", "female"),
        ("Piaskowy Wilk", "male"),
        ("Lis", "male"),
        ("Kuba", "male"),
        ("Koszałek Opałek", "male"),
        ("Błystek", "male"),
        ("Krasnale", "ensemble"),
        ("Wszyscy", "ensemble"),
        ("Chór", "ensemble"),
    ],
)
def test_guess_gender(name: str, gender: str) -> None:
    assert guess_gender(name) == gender


def test_bank_has_at_least_four_per_gender_and_a_narrator() -> None:
    genders = [v.gender for v in BANK]
    assert genders.count("female") >= 4
    assert genders.count("male") >= 4
    assert get_voice(NARRATOR).gender == "neutral"
    assert len({v.id for v in BANK}) == len(BANK)


def test_assignment_is_deterministic_and_distinct(script_json: dict[str, Any]) -> None:
    script = parse_script(script_json)
    first = assign_voices(script, {})
    assert first == assign_voices(parse_script(script_json), {})
    assert get_voice(first["krolowa"]).gender == "female"
    assert get_voice(first["piaskowy-wilk"]).gender == "male"
    assert first["piaskowy-wilk"] != first["blystek"]


def test_ensemble_gets_narrator(script_json: dict[str, Any]) -> None:
    script_json["characters"].append({"id": "krasnale", "name": "Krasnale"})
    assert assign_voices(parse_script(script_json), {})["krasnale"] == NARRATOR


def test_pool_wraps_round_robin_when_exhausted(script_json: dict[str, Any]) -> None:
    script_json["characters"] = [
        {"id": f"wilk-{i}", "name": f"Wilk {i}"} for i in range(10)
    ]
    voices = assign_voices(parse_script(script_json), {})
    males = [v.id for v in BANK if v.gender == "male"]
    assert [voices[f"wilk-{i}"] for i in range(len(males))] == males
    assert voices[f"wilk-{len(males)}"] == males[0]


def test_overrides_win(script_json: dict[str, Any]) -> None:
    script = parse_script(script_json)
    voices = assign_voices(script, {"krolowa": NARRATOR, "nieznany": NARRATOR})
    assert voices["krolowa"] == NARRATOR
    assert "nieznany" not in voices


def test_unknown_voice_override_is_rejected(script_json: dict[str, Any]) -> None:
    with pytest.raises(ValueError, match="unknown voice"):
        assign_voices(parse_script(script_json), {"krolowa": "nope"})


def test_line_voice(script_json: dict[str, Any]) -> None:
    script = parse_script(script_json)
    voices = assign_voices(script, {})
    assert voice_for_line(script.lines[4], voices) == NARRATOR
    assert voice_for_line(script.lines[5], voices) == voices["blystek"]
    assert voice_for_line(script.lines[1], voices) == voices["piaskowy-wilk"]


def test_speaker_missing_from_cast_is_assigned(script_json: dict[str, Any]) -> None:
    script_json["lines"][1]["speakers"] = ["macocha"]
    voices = assign_voices(parse_script(script_json), {})
    assert get_voice(voices["macocha"]).gender == "female"
