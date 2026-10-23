"""Bodies of flows F1-F5; the runner and shared navigation live in flows.py."""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

import oracle
from cdp import CdpError

if TYPE_CHECKING:
    from flows import Run

_HERE = Path(__file__).parent


def f1_import(run: Run) -> None:
    """F1: import the PDF through the real file picker; the library lists it."""
    run.step("open the app on the library screen")
    run.cdp.page.call("Network.enable")
    run.boot()
    run.step('click "Importuj plik" with the file chooser intercepted')
    run.cdp.page.call("Page.setInterceptFileChooserDialog", enabled=True)
    run.cdp.tap("Importuj plik")
    chooser = run.cdp.page.wait_event("Page.fileChooserOpened", 10)
    run.step(f"hand {run.pdf.name} to the picker's <input type=file>")
    run.cdp.page.call(
        "DOM.setFileInputFiles",
        files=[str(run.pdf)],
        backendNodeId=chooser["backendNodeId"],
    )
    run.step("the script opens on its roles screen (first visit)")
    run.cdp.wait_for("Twoje role", 40)
    run.shot("script-screen")
    run.step("IndexedDB holds the script")
    script = run.stored()
    run.check(script and script["lines"], "no stored script with lines")
    assert script is not None
    spoken = sum(1 for ln in script["lines"] if oracle.is_spoken(ln))
    run.note(f"stored: {len(script['lines'])} lines, {spoken} spoken")
    run.step("back on the library, the tile shows the spoken-line count")
    run.cdp.tap("Back")  # roles -> hub
    run.cdp.wait_for("Moje role", 10)
    run.cdp.tap("Back")  # hub -> library
    run.cdp.wait_for("Twoje skrypty", 10)
    tile = run.cdp.wait_for(f"{run.pdf.name} · {spoken} kwestii", 10)
    run.check(script["title"] in tile["text"], f"tile reads {tile['text']!r}")
    run.note(f"library tile: '{run.pdf.name} · {spoken} kwestii'")
    run.shot("library")
    offsite = sorted(
        {
            e["params"]["request"]["url"].split("?")[0]
            for e in run.cdp.page.events
            if e["method"] == "Network.requestWillBeSent"
            and not e["params"]["request"]["url"].startswith(
                ("http://127.0.0.1:8792", "data:", "blob:")
            )
        }
    )
    run.note(f"non-loopback requests: {offsite or 'none'}")


def f2_roles(run: Run) -> None:
    """F2: the role picker lists the role with its line count, and the songs."""
    run.step("a reload opens the last script's hub, not the library")
    run.boot()
    run.check(run.cdp.find("Moje role"), "the app opened on the library")
    run.note("reload -> script hub")
    _script, facts = run.open_script()
    run.step(f"chip '{facts.name} (n)' shows its spoken-line count")
    chip = run.chip(facts)
    want = f"{facts.name} ({len(facts.spoken)})"
    run.check(chip["text"] == want, f"chip {chip['text']!r}, expected {want!r}")
    run.note(f"chip '{chip['text']}' ({facts.dialogue_blocks} dialogue blocks)")
    run.step("every song has a card under 'Piosenki' (headed + unheaded ♪)")
    # The cards sit below the fold in a lazily built ListView: scroll down to
    # each in script order (find_scrolling only wheels down).
    missing: list[str] = []
    for title in facts.songs:
        try:
            run.cdp.find_scrolling(f"{title} (", 640)
        except CdpError:
            missing.append(title)
    run.check(not missing, f"no card for songs {missing}")
    preview = run.cdp.find("Śpiewa: ")
    run.check(preview, "song cards show no 'Śpiewa: ...' preview")
    run.note(
        f"songs: {len(facts.headed_songs)} headed + "
        f"{len(facts.unheaded_songs)} unheaded"
    )
    run.step("screenshot")
    run.shot("roles")


def audio_log(run: Run) -> list[dict[str, Any]]:
    """The instrumented audio calls so far (instrument.js)."""
    log = run.cdp.evaluate("window.__suflerAudio || []")
    return log if isinstance(log, list) else []


def f3_rehearse(run: Run) -> None:
    """F3: the role + a scene: partner name and audio, countdown, Space advances."""
    run.step(f"open the script, select only {run.role}")
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    run.hub("Sceny")
    pick = oracle.pick_scene(script, run.picked_roles(script))
    run.step(f"start scene '{pick.title}' (lines {pick.start}-{pick.end})")
    run.cdp.tap(f"kwestie {pick.start}–{pick.end}")
    run.cdp.wait_for(f"kwestia 1/{pick.cues}", 10)
    run.step("partner's name shown, its audio starts; text only if unvoiced")
    first = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    run.cdp.wait_for(oracle.speaker_names(script, first), 5)
    run.cdp.page.pump(2)
    log = audio_log(run)
    run.check(log, "no speechSynthesis.speak / media play within 2 s")
    run.note(f"audio: {json.dumps(log[0])}")
    held = "error" in log[0]  # device speech failed: the text is held instead
    shown = run.cdp.find(first["text"][:40]) is not None
    run.check(shown == held, f"partner text shown={shown}, audio failed={held}")
    run.shot("partner")
    k = pick.partner_before_mine
    run.step(f'"Dalej" x{k - 1} to the last partner line before the role\'s')
    skip = run.cdp.wait_for("Dalej", 5)
    for _ in range(k - 1):
        run.cdp.click(skip)
    run.cdp.wait_for(f"kwestia {k}/{pick.cues}", 10)
    run.step("that partner line ends by itself; the role's countdown starts")
    try:
        # A partner song before it is one step: all its lines play first.
        run.cdp.wait_for("Twoja kwestia", 25 + 10 * (pick.before_lines - 1))
    except Exception as e:
        log = audio_log(run)
        raise TimeoutError(
            f"{e}; {len(log)} audio calls, last {json.dumps(log[-1:])}"
        ) from e
    run.note(f"audio log: {json.dumps(audio_log(run)[-2:])}")
    run.step("the countdown runs; the role's own text is hidden")
    mine = pick.mine_text[:40]
    before = run.cdp.text()
    run.cdp.page.pump(1.5)
    run.check(run.cdp.text() != before, "countdown text did not change in 1.5 s")
    run.check(run.cdp.find("Mów z pamięci"), "no 'Mów z pamięci…' placeholder")
    run.check(not run.cdp.find(mine), f"own line {mine!r} shown before Space")
    run.shot("countdown")
    run.step("Space ends the line: its text is revealed; a grade advances")
    at = run.header()
    run.cdp.key_space()
    run.cdp.wait_for("Jak poszło?", 5)
    run.cdp.wait_for(mine, 5)
    run.note(f"kwestia {at}: own text hidden in the countdown, shown for the grade")
    run.shot("grade")
    run.cdp.tap("Dobrze", 5)
    run.cdp.page.pump(1)
    after = run.header()
    advanced = after is None or (at is not None and after[0] > at[0])
    run.check(advanced, f"header {at} -> {after} after Space")
    run.note(f"Space: kwestia {at} -> {after or 'finished'}")
    run.shot("after-space")


def f4_anki(run: Run) -> None:
    """F4: export the role's deck; notes == its spoken lines, cue -> line."""
    run.step(f"open the script, select only {run.role}")
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    run.hub("Narzędzia")
    run.step("allow downloads into the artefact dir")
    downloads = run.dir / "downloads"
    downloads.mkdir()
    run.cdp.browser.call(
        "Browser.setDownloadBehavior",
        behavior="allowAndName",
        downloadPath=str(downloads),
        eventsEnabled=True,
    )
    run.step('click "Eksportuj talię Anki"')
    run.cdp.click(run.cdp.find_scrolling("Eksportuj talię Anki", 300))
    begin = run.cdp.browser.wait_event("Browser.downloadWillBegin", 20)
    run.cdp.browser.wait_event(
        "Browser.downloadProgress",
        20,
        lambda p: p["guid"] == begin["guid"] and p["state"] == "completed",
    )
    apkg = downloads / begin["guid"]
    run.note(f"download '{begin['suggestedFilename']}' -> {apkg}")
    run.step("open the .apkg with sqlite3 (python -I)")
    out = subprocess.run(
        [sys.executable, "-I", str(_HERE / "apkg_check.py"), str(apkg)],
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )
    run.check(out.returncode == 0, f"apkg_check: {out.stderr.strip()[-300:]}")
    notes: list[list[str]] = json.loads(out.stdout)
    run.step("notes == the picked roles' lines; fronts are cues, backs own lines")
    # The deck covers every picked role: the character plus the groups that
    # ticking it pre-ticks ("Wszyscy" lines are the actor's to say too).
    roles = run.picked_roles(script)
    want = oracle.expected_cards(script, roles)
    run.check(
        len(notes) == len(want) >= len(facts.spoken),
        f"{len(notes)} notes, {len(want)} expected cards for {sorted(roles)}, "
        f"{len(facts.spoken)} {facts.name} spoken lines",
    )
    backs = sorted(n[1] for n in notes)
    run.check(
        backs == sorted(b for _, b in want), f"backs differ from {sorted(roles)} lines"
    )
    unmatched = [
        oracle.unescape(b)[:30]
        for f, b in want
        if not any(n[1] == b and f in n[0] for n in notes)
    ]
    run.check(not unmatched, f"front lacks its cue for {unmatched}")
    groups = sorted(roles - {f"character:{run.role}"})
    run.note(
        f"{len(notes)} notes == {len(facts.spoken)} {facts.name} spoken lines "
        f"+ {len(want) - len(facts.spoken)} from pre-ticked groups {groups}"
    )


def f5_voices(run: Run) -> None:
    """F5: "Generuj głosy" starts a render and shows progress."""
    run.step("voice service healthy through the wrapper proxy")
    url = "http://127.0.0.1:8792/api/tts/health"
    with urllib.request.urlopen(url, timeout=5) as resp:
        run.note(f"health: {resp.read().decode()[:90]}")
    run.step("open the script")
    run.cdp.page.call("Network.enable")
    run.boot()
    run.open_script()
    run.hub("Narzędzia")
    run.step('click "Generuj głosy"')
    run.cdp.click(run.cdp.find_scrolling("Generuj głosy", 300))
    run.step("at least one /api/tts/jobs progress answer")
    got = run.cdp.page.wait_event(
        "Network.responseReceived",
        20,
        lambda p: "/api/tts/jobs/" in p["response"]["url"],
    )
    body = run.cdp.page.call("Network.getResponseBody", requestId=got["requestId"])
    job = json.loads(body["body"])
    run.check({"done", "total"} <= job.keys(), f"job reply {job}")
    run.note(f"progress: {job.get('state')} {job['done']}/{job['total']}")
    run.shot("voices-progress")
    # Not a check: only a warm clip cache finishes in time. Shows that an
    # unchanged script comes back from the cache instead of the GPU.
    start = time.monotonic()
    try:
        saved = run.cdp.wait_for("Głosy zapisane (", 25)["text"]
        run.note(f"'{saved}' after {time.monotonic() - start:.1f} s")
    except CdpError:
        run.note("pack not stored within 25 s (clips still rendering)")
