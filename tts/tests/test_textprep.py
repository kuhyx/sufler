"""Text clean-up and long-block splitting."""

from __future__ import annotations

from sufler_tts.textprep import clean_text, split_text


def test_clean_strips_parens_and_collapses_whitespace() -> None:
    assert (
        clean_text("Dzień (Wzdycha) dobry,\n  wilku /.../ !") == "Dzień dobry, wilku !"
    )


def test_clean_handles_nested_and_unclosed_parens() -> None:
    assert clean_text("A (b (c) d) e (f") == "A e (f"


def test_clean_of_direction_only_is_empty() -> None:
    assert clean_text(" (Śmieje się) ") == ""


def test_short_text_is_one_chunk() -> None:
    assert split_text("Krótko. I zwięźle!", max_chars=100) == ["Krótko. I zwięźle!"]


def test_long_text_splits_at_sentence_boundaries() -> None:
    text = "Pierwsze zdanie jest tutaj. Drugie zdanie też. Trzecie zdanie!"
    chunks = split_text(text, max_chars=30)
    assert chunks == [
        "Pierwsze zdanie jest tutaj.",
        "Drugie zdanie też.",
        "Trzecie zdanie!",
    ]
    assert " ".join(chunks) == text


def test_sentences_are_packed_up_to_the_limit() -> None:
    assert split_text("Aa. Bb. Cc. Dd.", max_chars=8) == ["Aa. Bb.", "Cc. Dd."]


def test_overlong_sentence_falls_back_to_commas_then_words() -> None:
    text = "jeden, dwa, trzy, cztery, pięć sześć siedem osiem dziewięć"
    chunks = split_text(text, max_chars=20)
    assert all(len(c) <= 20 for c in chunks)
    assert " ".join(chunks) == text


def test_single_word_longer_than_limit_is_kept_whole() -> None:
    assert split_text("Konstantynopolitańczykowianeczka", max_chars=10) == [
        "Konstantynopolitańczykowianeczka"
    ]
