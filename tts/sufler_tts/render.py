"""Render every spoken line of a script into a cached clip, then build the pack."""

from __future__ import annotations

import tempfile
from collections.abc import Callable
from pathlib import Path

from sufler_tts.assign import assign_voices, voice_for_line
from sufler_tts.audio import concat, encode
from sufler_tts.cache import ClipCache, clip_key, seed_for
from sufler_tts.engine import Engine
from sufler_tts.pack import build_pack, pack_name, script_fingerprint
from sufler_tts.script import Script
from sufler_tts.textprep import clean_text, split_text
from sufler_tts.voices import Voice, get_voice

Progress = Callable[[int, int], None]

__all__ = ["pack_name", "render_clip", "render_script", "spoken_lines"]


def spoken_lines(script: Script) -> list[tuple[int, str]]:
    """(index, cleaned text) of every line that gets a clip.

    Same rule as Dart `isSpoken`; a line whose text is nothing but leftover
    directions cleans to "" and gets no clip (the app treats a missing clip
    as silence).
    """
    lines = [(ln.index, clean_text(ln.text)) for ln in script.lines if ln.is_spoken]
    return [(i, text) for i, text in lines if text]


def render_clip(text: str, voice: Voice, engine: Engine, cache: ClipCache) -> Path:
    """The cached Ogg clip for `text` in `voice`, synthesizing it on a miss."""
    key = clip_key(text, voice, engine.name)
    hit = cache.get(key)
    if hit is not None:
        return hit
    seed = seed_for(key)
    cache.root.mkdir(parents=True, exist_ok=True)
    chunks = [engine.synthesize(c, voice, seed) for c in split_text(text)]
    samples = concat(chunks, engine.sample_rate)
    with tempfile.TemporaryDirectory(dir=cache.root) as tmp:
        out = Path(tmp) / "clip.ogg"
        encode(samples, engine.sample_rate, voice.pitch, out)
        return cache.put(key, out)


def render_script(
    script: Script,
    overrides: dict[str, str],
    engine: Engine,
    cache: ClipCache,
    packs: Path,
    progress: Progress,
) -> Path:
    """Render (or reuse) every clip and write `<packs>/<id>.sufler-audio.zip`."""
    voices = assign_voices(script, overrides)
    by_index = {ln.index: ln for ln in script.lines}
    todo = spoken_lines(script)
    progress(0, len(todo))
    clips: dict[int, Path] = {}
    for done, (index, text) in enumerate(todo, start=1):
        voice = get_voice(voice_for_line(by_index[index], voices))
        clips[index] = render_clip(text, voice, engine, cache)
        progress(done, len(todo))
    fingerprint = script_fingerprint(script)
    return build_pack(script.id, engine.name, voices, clips, packs, fingerprint)
