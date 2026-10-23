"""F7: speech recognition through the desktop wrapper (`/api/tts/transcribe`)."""

from __future__ import annotations

import difflib
import json
import subprocess
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import TYPE_CHECKING

import oracle

if TYPE_CHECKING:
    from flows import Run

_APP = "http://127.0.0.1:8792"


def _letters(text: str) -> str:
    """Lowercase words of ``text``, punctuation dropped (for similarity)."""
    kept = "".join(ch if ch.isalnum() else " " for ch in text.lower())
    return " ".join(kept.split())


def _wav(pack: Path, index: int, out: Path) -> Path:
    """The pack's clip for line ``index`` as the app's capture sends it:
    mono PCM16 WAV at 16 kHz (lib/rehearsal/wav.dart, mic_recorder.dart)."""
    with zipfile.ZipFile(pack) as z:
        manifest = json.loads(z.read("manifest.json"))
        clip = out / "clip.ogg"
        clip.write_bytes(z.read(manifest["lines"][str(index)]))
    wav = out / "take.wav"
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(clip)]
        + ["-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", str(wav)],
        check=True,
        timeout=20,
    )
    return wav


def _check_words(run: Run, words: object, seconds: float) -> None:
    """DOCS-contract `words`: every word with its own times, in order,
    inside the clip (what the desktop run split cuts a whole run by)."""
    run.check(isinstance(words, list) and words, f"no 'words' in reply: {words}")
    assert isinstance(words, list)
    last = 0.0
    for w in words:
        ok = isinstance(w, dict) and isinstance(w.get("word"), str)
        start, end = (w.get("start"), w.get("end")) if ok else (None, None)
        ok = ok and isinstance(start, (int, float)) and isinstance(end, (int, float))
        run.check(ok and last <= start <= end <= seconds + 0.1, f"word {w}")
        last = start
    run.note(
        f"{len(words)} words, {words[0]['start']}-{words[-1]['end']} s of {seconds:.2f} s"
    )


def f7_transcribe(run: Run) -> None:
    """F7: a WAV posted like TranscribeClient comes back as a matching transcript."""
    run.step("the voice service has a recognizer (health through the wrapper)")
    with urllib.request.urlopen(f"{_APP}/api/tts/health", timeout=5) as resp:
        stt = json.loads(resp.read()).get("stt")
    run.check(stt, "health reports no 'stt' recognizer")
    run.note(f"stt: {stt}")
    run.step(f"the first partner line before {run.role}'s, its pack clip as WAV")
    run.check(run.pack.is_file(), f"no pack at {run.pack}; render it first")
    script = run.stored()
    run.check(script, f"{run.pdf.name} not in the library; run F1 first")
    assert script is not None  # for the type checker
    roles = {f"character:{run.role}"} | oracle.own_groups(script, run.role)
    pick = oracle.pick_scene(script, roles)
    line = next(
        ln for ln in script["lines"][pick.start : pick.end + 1] if oracle.is_spoken(ln)
    )
    with tempfile.TemporaryDirectory() as tmp:
        wav = _wav(run.pack, line["index"], Path(tmp))
        body = wav.read_bytes()
        run.step("POST /api/tts/transcribe?lang=pl through the wrapper")
        req = urllib.request.Request(
            f"{_APP}/api/tts/transcribe?lang=pl",
            data=body,
            headers={"content-type": "audio/wav"},
            method="POST",
        )
        start = time.monotonic()
        with urllib.request.urlopen(req, timeout=40) as resp:
            status, got = resp.status, json.loads(resp.read())
        took = time.monotonic() - start
    text = (got.get("text") or "").strip()
    run.check(status == 200 and text, f"HTTP {status}, reply keys {sorted(got)}")
    run.note(
        f"line {line['index']}: {len(body)} B WAV -> HTTP 200 in {took:.1f} s, "
        f"{len(text)}-char transcript, speech {got.get('speechStart')}-"
        f"{got.get('speechEnd')} s"
    )
    seconds = (len(body) - 44) / 32000  # mono PCM16 at 16 kHz after the header
    _check_words(run, got.get("words"), seconds)
    run.step("the transcript resembles the line's stored text")
    ratio = difflib.SequenceMatcher(
        None, _letters(text), _letters(line["text"])
    ).ratio()
    run.check(ratio >= 0.6, f"similarity {ratio:.2f} < 0.6")
    run.note(f"similarity to the stored line {ratio:.2f}")
