"""F3: rehearse the role through one scene (whole runs, partner text hidden)."""

from __future__ import annotations

import itertools
import json
from typing import TYPE_CHECKING, Any

import oracle

if TYPE_CHECKING:
    from flows import Run


def audio_log(run: Run) -> list[dict[str, Any]]:
    """The instrumented audio calls so far (instrument.js)."""
    log = run.cdp.evaluate("window.__suflerAudio || []")
    return log if isinstance(log, list) else []


def _tail(text: str) -> str:
    """A findable piece of the end of ``text``: its last 40 chars on one line
    (a step's revealed text is one label with the lines joined)."""
    return text.strip().splitlines()[-1][-40:]


def _played_back_to_back(run: Run, calls: list[dict[str, Any]], lines: int) -> None:
    """The partner step before the role's: one playback per line, and a
    voiced one (media clip) plays each clip to its end before the next.

    After fast "Dalej" skips the web player repeats play() on the clip that
    is already playing (same element, not paused): those are no-ops, not
    playbacks, so only calls that started a paused element count.
    """
    starts = [c for c in calls if c["kind"] == "speech" or c.get("paused")]
    run.check(
        len(starts) == lines,
        f"{len(starts)} playbacks for a {lines}-line partner step: {calls}",
    )
    media = [c for c in starts if c["kind"] == "media"]
    run.check(len({c["el"] for c in media}) == len(media), f"clip replayed: {calls}")
    for a, b in itertools.pairwise(media):
        run.check("ended" in a and b["t"] >= a["ended"], f"overlap: {a} / {b}")


def f3_rehearse(run: Run) -> None:
    """F3: the role + a scene: who speaks and audio, countdown, Space reveals."""
    run.step(f"open the script, select only {run.role}")
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    run.hub("Sceny")
    pick = oracle.pick_scene(script, run.picked_roles(script))
    run.step(f"start scene '{pick.title}': {pick.cues} steps (oracle.steps)")
    run.cdp.tap(f"kwestie {pick.start}–{pick.end}")
    run.cdp.wait_for(f"kwestia 1/{pick.cues}", 10)
    run.check(run.header() == (1, pick.cues), f"header {run.header()}")
    run.step(f"'{pick.first_label}' shown, audio starts; text only if unvoiced")
    first = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    # The label's node also carries the text (or "mówi…") below it.
    who = run.cdp.wait_for(pick.first_label, 5)["text"].split("\n")[0]
    run.check(who == pick.first_label, f"label {who!r}")
    run.cdp.page.pump(2)
    log = audio_log(run)
    run.check(log, "no speechSynthesis.speak / media play within 2 s")
    run.note(f"audio: {json.dumps(log[0])}")
    held = "error" in log[0]  # could not be voiced: the text is held instead
    shown = run.cdp.find(first["text"][:40]) is not None
    run.check(shown == held, f"partner text shown={shown}, audio failed={held}")
    speaking = run.cdp.find("mówi…") is not None
    run.check(speaking != held, f"'mówi…' shown={speaking}, audio failed={held}")
    run.note(f"'{who}': text {'held (unvoiced)' if held else 'hidden, mówi…'}")
    run.shot("partner")
    k = pick.partner_before_mine
    run.step(f'"Dalej" x{k - 1} to the last partner step before the role\'s')
    skip = run.cdp.wait_for("Dalej", 5)
    since = 0.0
    for i in range(k - 1):
        if i == k - 2:  # the calls after this click are the step's own
            now = run.cdp.evaluate("performance.now()")
            since = float(now) if isinstance(now, (int, float)) else 0.0
        run.cdp.click(skip)
    run.cdp.wait_for(f"kwestia {k}/{pick.cues}", 10)
    run.step(f"its {pick.before_lines} line(s) play back to back; countdown starts")
    try:
        run.cdp.wait_for("Twoja kwestia", 25 + 10 * (pick.before_lines - 1))
    except Exception as e:
        log = audio_log(run)
        raise TimeoutError(
            f"{e}; {len(log)} audio calls, last {json.dumps(log[-1:])}"
        ) from e
    calls = [c for c in audio_log(run) if c["t"] > since]
    _played_back_to_back(run, calls, pick.before_lines)
    run.note(f"partner step: {len(calls)} play calls, last {json.dumps(calls[-1])}")
    run.step("one countdown for the whole own step; its text is hidden")
    head, tail = pick.mine_text[:40], _tail(pick.mine_last)
    before = run.cdp.text()
    run.cdp.page.pump(1.5)
    run.check(run.cdp.text() != before, "countdown text did not change in 1.5 s")
    run.check(run.cdp.find("Mów z pamięci"), "no 'Mów z pamięci…' placeholder")
    for part in (head, tail):
        run.check(not run.cdp.find(part), f"own text {part!r} shown before Space")
    run.shot("countdown")
    run.step("Space reveals the whole step under 'Jak poszło?'; one grade advances")
    at = run.header()
    run.cdp.key_space()
    run.cdp.wait_for("Jak poszło?", 5)
    run.cdp.wait_for(head, 5)
    run.check(run.cdp.find(tail), f"own step's last line {tail!r} not revealed")
    run.shot("grade")
    run.cdp.tap("Dobrze", 5)
    run.cdp.page.pump(1)
    after = run.header()
    want = None if at is None or at[0] == at[1] else (at[0] + 1, at[1])
    run.check(at is not None and after == want, f"header {at} -> {after}, want {want}")
    run.note(f"own step at kwestia {at}: hidden, then revealed whole; -> {after}")
    run.shot("after-space")
