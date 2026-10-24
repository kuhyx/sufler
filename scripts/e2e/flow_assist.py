"""F8, F9: the PC assistant during a rehearsal (look a word up, correct a line).

Both go over HTTP through the wrapper to the voice service (`/api/tts/explain`,
`/api/tts/render_line`); the probe in instrument.js logs those requests into
``window.__suflerNet`` (status, times, bytes, a rendered clip's duration).
"""

from __future__ import annotations

import json
import re
import time
from typing import TYPE_CHECKING, Any

import oracle
from flow_pack import _clip_seconds
from flow_rehearse import audio_log

if TYPE_CHECKING:
    from flows import Json, Run

# Shown on a corrected line until the PC has rendered its clip.
TTS_UNTIL_RENDERED = "głos: syntezator do czasu wygenerowania"
# Appended to the corrected line: long enough that its new clip is seconds
# longer than the old one, not tenths.
EXTRA = " I powtórzę to jeszcze raz, powoli i wyraźnie, żeby wszyscy usłyszeli."


def net_log(run: Run) -> list[dict[str, Any]]:
    """The `/api/` requests so far (instrument.js)."""
    log = run.cdp.evaluate("window.__suflerNet || []")
    return log if isinstance(log, list) else []


def _start_scene(run: Run) -> tuple[Json, oracle.ScenePick]:
    """Reload, select only the role, start its scene at kwestia 1."""
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    run.hub("Sceny")
    pick = oracle.pick_scene(script, run.picked_roles(script))
    run.cdp.tap(f"kwestie {pick.start}–{pick.end}")
    run.cdp.wait_for(f"kwestia 1/{pick.cues}", 10)
    return script, pick


def _press_word(run: Run, hit: Json) -> str:
    """Long-press a word near the left edge of ``hit``; returns the sheet's
    „<word>”. Semantics merge the step's labels ("(Chór)", "Jak poszło?")
    with its text into one node, so the presses walk down it in text rows
    until one lands on the text (the only long-pressable part)."""
    rows = range(14, 260, 30)
    # 100 px in: a word past the first; 30 px: a short line ("Uważaj!").
    for dy, dx in ((dy, dx) for dy in rows for dx in (100, 30)):
        run.cdp.long_press(hit["left"] + dx, hit["top"] + dy)
        run.cdp.page.pump(0.6)
        title = re.search(r"„([^”]+)”", run.cdp.text())
        if title:
            return title[1]
    run.check(False, "no lookup sheet after long-presses down the step")
    return ""


def f8_lookup(run: Run) -> None:
    """F8: long-press a word of the revealed own text, ask Claude, read it."""
    began = time.monotonic()
    run.step(f"open the script, select only {run.role}, start its scene")
    script, pick = _start_scene(run)
    k = pick.partner_before_mine
    run.step(f'"Dalej" x{k} to the role\'s step; Space reveals its text')
    skip = run.cdp.wait_for("Dalej", 5)
    for _ in range(k):
        run.cdp.click(skip)
    run.cdp.wait_for("Twoja kwestia", 10)
    run.cdp.key_space()
    run.cdp.wait_for("Jak poszło?", 5)
    hit = run.cdp.wait_for(pick.mine_text[:40], 5)
    run.step("long-press a word of it: sheet „<word>” with the dictionaries")
    word = _press_word(run, hit)
    run.check(run.cdp.find("Słownik") and run.cdp.find("Wikisłownik"), "no links")
    run.note(f"sheet „{word}”")
    run.shot("sheet")
    run.step('"Zapytaj Claude": spinner, POST /api/tts/explain')
    before = len(net_log(run))
    asked = time.monotonic()
    run.cdp.tap("Zapytaj Claude", 5)
    run.cdp.page.pump(0.5)
    run.check(not run.cdp.find("Zapytaj Claude"), "button still shown after tap")
    sent = [e for e in net_log(run)[before:] if "explain" in e["path"]]
    run.check(sent, f"no explain request: {net_log(run)[before:]}")
    run.shot("spinner")
    run.step("a Polish answer arrives (sheet + note on the line)")
    budget = 55 - (time.monotonic() - began)
    entry: dict[str, Any] = {}
    while time.monotonic() - asked < budget:
        entry = [e for e in net_log(run) if "explain" in e["path"]][-1]
        if "done" in entry or "error" in entry:
            break
        run.cdp.page.pump(0.5)
    took = time.monotonic() - asked
    run.check(entry.get("status") == 200, f"explain after {took:.1f} s: {entry}")
    prefs = run.cdp.helper(f"json({json.dumps('prefs/' + script['id'])})", wait=True)
    notes = prefs.get("notes", {}) if isinstance(prefs, dict) else {}
    found = [n for ns in notes.values() for n in ns if n.get("about") == word]
    run.check(found, f"no note about {word!r} in prefs: {list(notes)}")
    answer = found[-1]["text"]
    run.check(run.cdp.find(answer[:40]), "answer not shown in the sheet")
    polish = re.search(r"[ąćęłńóśźż]", answer, re.IGNORECASE)
    run.check(polish, f"answer has no Polish letters: {answer[:100]!r}")
    run.note(f"explain 200 in {(entry['done'] - entry['t']) / 1000:.1f} s")
    run.note(f"answer: {answer[:100]!r}")
    run.shot("answer")


def _correct_first(run: Run, line: Json) -> None:
    """✎ on the current step, pick ``line`` if asked, append EXTRA, save."""
    run.cdp.tap("Popraw kwestię", 5)
    run.cdp.page.pump(0.5)
    if run.cdp.find("Którą kwestię poprawić?"):
        run.cdp.tap(line["text"][:30], 5)
    run.cdp.tap("Tekst", 5)
    run.cdp.key("End", 35)
    run.cdp.insert_text(EXTRA)
    run.cdp.page.pump(0.3)
    run.cdp.tap("Zapisz", 5)


def _replay_first(run: Run) -> float:
    """Step back to kwestia 1 so its first line plays again; returns
    performance.now() just before the click that replays it."""
    at = run.header()
    run.check(at is not None, "no rehearsal header")
    assert at is not None
    if at[0] == 1:
        run.cdp.tap("Dalej", 5)
        run.cdp.wait_for(f"kwestia 2/{at[1]}", 5)
    while (h := run.header()) and h[0] > 2:
        run.cdp.tap("Wstecz", 5)
        run.cdp.wait_for(f"kwestia {h[0] - 1}/{h[1]}", 5)
    now = run.cdp.evaluate("performance.now()")
    run.cdp.tap("Wstecz", 5)
    run.cdp.wait_for(f"kwestia 1/{at[1]}", 5)
    return float(now) if isinstance(now, (int, float)) else 0.0


def f9_correct(run: Run) -> None:
    """F9: ✎ a partner line that has a pack clip; the PC renders the new
    text and that clip plays from then on (needs F6's pack)."""
    began = time.monotonic()
    run.step(f"open the script, select only {run.role}, start its scene")
    script, pick = _start_scene(run)
    first = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    run.cdp.page.pump(1)
    played = audio_log(run)
    run.check(played and played[0]["kind"] == "media", f"not a pack clip: {played}")
    # The clip as played: a rerun on the same profile already replaced the
    # pack file's (_clip_seconds) with an earlier correction's.
    old = float(played[0].get("duration") or _clip_seconds(run.pack, first["index"]))
    run.step(f'✎ line {first["index"]} (pack clip {old:.2f} s): append text, "Zapisz"')
    before = len(net_log(run))
    _correct_first(run, first)
    run.step(f'"zmieniono" and "{TTS_UNTIL_RENDERED}" on the step')
    # Both show once the correction is saved (a rerun has "zmieniono"
    # already, so wait for the device-TTS note, which only a save brings).
    run.cdp.wait_for(TTS_UNTIL_RENDERED, 5)
    run.cdp.wait_for("zmieniono", 5)
    run.shot("corrected")
    run.note(f"line {first['index']}: 'zmieniono' + '{TTS_UNTIL_RENDERED}'")
    run.step("POST /api/tts/render_line answers 200 with a clip")
    entry: dict[str, Any] = {}
    while time.monotonic() - began < 45:
        renders = [e for e in net_log(run)[before:] if "render_line" in e["path"]]
        entry = renders[-1] if renders else {}
        if "clipSeconds" in entry or "error" in entry:
            break
        run.cdp.page.pump(0.5)
    run.check(entry.get("status") == 200 and entry.get("bytes"), f"render: {entry}")
    new = float(entry["clipSeconds"])
    run.check(abs(new - old) > 1, f"new clip {new:.2f} s vs old {old:.2f} s")
    took = (entry["done"] - entry["t"]) / 1000
    run.note(f"render_line 200, {entry['bytes']} B in {took:.1f} s: {new:.2f} s clip")
    run.step("the step replays the NEW clip (media, not device TTS)")
    # The walk went on meanwhile (short partner steps): back to kwestia 1.
    since = _replay_first(run)
    run.cdp.page.pump(1.5)
    run.check(run.cdp.find("zmieniono"), "no 'zmieniono' on the replayed step")
    run.check(not run.cdp.find(TTS_UNTIL_RENDERED), "still 'syntezator' after render")
    calls = [c for c in audio_log(run) if c["t"] >= since]
    run.check(calls, "no audio after the replay")
    got = calls[0]
    run.check(got["kind"] == "media" and "error" not in got, f"replay {got}")
    run.check(abs(float(got.get("duration", 0)) - new) < 0.1, f"replay {got}")
    run.note(f"replay: media {got['duration']:.2f} s == new clip (old {old:.2f} s)")
    run.shot("replayed")
