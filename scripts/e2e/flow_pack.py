"""F6: a rendered voice pack, imported through the app, voices partner lines."""

from __future__ import annotations

import json
import subprocess
import tempfile
import zipfile
from pathlib import Path
from typing import TYPE_CHECKING

import oracle
from flow_rehearse import audio_log

if TYPE_CHECKING:
    from flows import Run


def _clip_seconds(pack: Path, index: int) -> float:
    """ffprobe duration of the pack's clip for line ``index``."""
    with zipfile.ZipFile(pack) as z, tempfile.TemporaryDirectory() as tmp:
        manifest = json.loads(z.read("manifest.json"))
        clip = Path(tmp) / "clip.ogg"
        clip.write_bytes(z.read(manifest["lines"][str(index)]))
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration"]
            + ["-of", "csv=p=0", str(clip)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    return float(out.stdout)


def f6_pack(run: Run) -> None:
    """F6: import the pack via the app; after a reload a partner clip plays."""
    pack = run.pack
    run.step(f"open the script ({pack.name} must exist)")
    run.check(pack.is_file(), f"no pack at {pack}; render it first")
    run.boot()
    script, facts = run.open_script()
    spoken = sum(1 for ln in script["lines"] if oracle.is_spoken(ln))
    run.hub("Narzędzia")
    run.step('click "Importuj paczkę audio (.zip)" with the chooser intercepted')
    run.cdp.page.call("Page.setInterceptFileChooserDialog", enabled=True)
    run.cdp.click(run.cdp.find_scrolling("Importuj paczkę audio (.zip)", 300))
    chooser = run.cdp.page.wait_event("Page.fileChooserOpened", 10)
    run.cdp.page.call(
        "DOM.setFileInputFiles",
        files=[str(pack)],
        backendNodeId=chooser["backendNodeId"],
    )
    run.step(f'toast "Głosy zapisane ({spoken} kwestii)"')
    # The toast, not the "Paczka: …" status: F5 may have stored a pack already.
    saved = run.cdp.wait_for("Głosy zapisane (", 30)["text"]
    run.check(f"({spoken} kwestii)" in saved, f"toast reads {saved!r}")
    run.note(f"'{saved}'")
    run.shot("pack-imported")
    run.step(f"reload, reopen (pack from IndexedDB), select only {run.role}")
    run.boot()
    script, facts = run.open_script()
    run.select_only_role(facts)
    run.hub("Sceny")
    pick = oracle.pick_scene(script, run.picked_roles(script))
    run.step(f"start scene '{pick.title}' (lines {pick.start}-{pick.end})")
    run.cdp.tap(f"kwestie {pick.start}–{pick.end}")
    run.cdp.wait_for(f"kwestia 1/{pick.cues}", 10)
    first = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    run.step(f"line {first['index']} plays as a media clip, not device speech")
    run.cdp.page.pump(2)
    log = audio_log(run)
    run.check(log, "no audio call within 2 s")
    entry = log[0]
    run.check(
        entry["kind"] == "media" and "playing" in entry and "error" not in entry,
        f"first audio call {json.dumps(entry)}",
    )
    run.check(not any(e["kind"] == "speech" for e in log), "device TTS was used")
    want = _clip_seconds(pack, first["index"])
    got = entry.get("duration")
    run.check(
        isinstance(got, (int, float)) and abs(got - want) < 0.1,
        f"played {got} s, pack clip {first['index']} is {want:.2f} s",
    )
    run.note(f"media play {json.dumps(entry)}; pack clip {want:.2f} s")
    # Voiced from the pack, so by default only who speaks is on screen.
    hidden = run.cdp.find(first["text"][:40]) is None
    run.check(hidden, "partner text shown while its pack clip plays")
    run.check(run.cdp.find("mówi…"), "no 'mówi…' in place of the partner text")
    run.note("partner text hidden, 'mówi…' shown")
    run.shot("pack-playing")
