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
    run.step("the script screen opens (role picker shown)")
    run.cdp.wait_for("Twoje role", 40)
    run.shot("script-screen")
    run.step("IndexedDB holds the script")
    script = run.stored()
    run.check(script and script["lines"], "no stored script with lines")
    assert script is not None
    spoken = sum(1 for ln in script["lines"] if oracle.is_spoken(ln))
    run.note(f"stored: {len(script['lines'])} lines, {spoken} spoken")
    run.step("back on the library, the tile shows the spoken-line count")
    run.cdp.tap("Back")
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
    run.step("open the imported script")
    run.boot()
    _script, facts = run.open_script()
    run.step(f"chip '{facts.name} (n)' shows its spoken-line count")
    chip = run.chip(facts)
    want = f"{facts.name} ({len(facts.spoken)})"
    run.check(chip["text"] == want, f"chip {chip['text']!r}, expected {want!r}")
    run.note(f"chip '{chip['text']}' ({facts.dialogue_blocks} dialogue blocks)")
    run.step("every song has a chip (headed + unheaded ♪)")
    missing = [
        t
        for t in facts.headed_songs + facts.unheaded_songs
        if not run.cdp.find(f"{t} (")
    ]
    run.check(not missing, f"no chip for songs {missing}")
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
    """F3: the role + a scene: partner text and audio, countdown, Space advances."""
    run.step(f"open the script, select only {run.role}")
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    pick = oracle.pick_scene(script, run.role)
    run.step(f"start scene '{pick.title}' (lines {pick.start}-{pick.end})")
    run.cdp.tap(f"kwestie {pick.start}–{pick.end}")
    run.cdp.wait_for(f"kwestia 1/{pick.cues}", 10)
    run.step("partner line shown and its audio starts")
    first = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    run.cdp.wait_for(first["text"][:40], 5)
    run.shot("partner")
    run.cdp.page.pump(2)
    log = audio_log(run)
    run.check(log, "no speechSynthesis.speak / media play within 2 s")
    run.note(f"audio: {json.dumps(log[0])}")
    k = pick.partner_before_mine
    run.step(f'"Dalej" x{k - 1} to the last partner line before the role\'s')
    skip = run.cdp.wait_for("Dalej", 5)
    for _ in range(k - 1):
        run.cdp.click(skip)
    run.cdp.wait_for(f"kwestia {k}/{pick.cues}", 10)
    run.step("that partner line ends by itself; the role's countdown starts")
    try:
        run.cdp.wait_for("Twoja kwestia", 25)
    except Exception as e:
        log = audio_log(run)
        raise TimeoutError(
            f"{e}; {len(log)} audio calls, last {json.dumps(log[-1:])}"
        ) from e
    run.note(f"audio log: {json.dumps(audio_log(run)[-2:])}")
    run.step("the countdown runs")
    before = run.cdp.text()
    run.cdp.page.pump(1.5)
    run.check(run.cdp.text() != before, "countdown text did not change in 1.5 s")
    run.shot("countdown")
    run.step("Space ends the line and the rehearsal advances")
    at = run.header()
    run.cdp.key_space()
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
    run.step("note count == role spoken lines; fronts are cues, backs role lines")
    want = oracle.expected_cards(script, run.role)
    run.check(
        len(notes) == len(want) == len(facts.spoken),
        f"{len(notes)} notes, {len(want)} expected cards, "
        f"{len(facts.spoken)} {facts.name} spoken lines",
    )
    backs = sorted(n[1] for n in notes)
    run.check(
        backs == sorted(b for _, b in want), f"backs differ from {facts.name} lines"
    )
    unmatched = [
        oracle.unescape(b)[:30]
        for f, b in want
        if not any(n[1] == b and f in n[0] for n in notes)
    ]
    run.check(not unmatched, f"front lacks its cue for {unmatched}")
    run.note(f"{len(notes)} notes == {len(facts.spoken)} {facts.name} spoken lines")


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
