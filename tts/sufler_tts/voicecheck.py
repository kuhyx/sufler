"""GPU checks: voice samples + distinctness, and real-time factor / VRAM.

    python -m sufler_tts.voicecheck render f1 f2 ...   # samples + measurements
    python -m sufler_tts.voicecheck report             # exit 1 if not distinct
    python -m sufler_tts.voicecheck rtf                # 5 Polish lines

Split `render` across calls (a few voices each) to stay under the action cap;
results accumulate in ~/.local/share/sufler/voice-check/.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

from sufler_tts.assets import CHECKS, SAMPLES
from sufler_tts.audio import decode, encode
from sufler_tts.chatterbox_engine import ChatterboxEngine
from sufler_tts.distinct import Record, distinctness, format_rows
from sufler_tts.voices import BANK, get_voice

SENTENCES = (
    "Dzień dobry, wilku! Co słychać dzisiaj w lesie? Opowiedz mi wszystko.",
    "Nie bój się, to tylko wiatr szumi w gałęziach starego dębu.",
    "Jutro rano pójdziemy razem na targ i kupimy trzy kosze jabłek.",
)
RTF_LINES = (
    ("m2", "Piaskowe Wilki nie jedzą krasnali, przysięgam na mój ogon!"),
    ("f1", "Królowa nie lubi czekać. Gdzie są moje lustra?"),
    ("m3", "Hej, ho, do pracy czas, kopiemy złoto cały czas."),
    ("f3", "Śnieżynki tańczą nad dachami, cicho, cichutko, jak co roku."),
    ("narrator", "A potem wszyscy wrócili do domu i zrobiło się bardzo cicho."),
)


def _median_f0(wav16k: np.ndarray) -> float:
    import librosa  # noqa: PLC0415 - Chatterbox's own pin; heavy import

    f0, _, _ = librosa.pyin(wav16k, fmin=50.0, fmax=600.0, sr=16_000)
    return float(np.nanmedian(f0))


def render(engine: ChatterboxEngine, voice_ids: list[str]) -> None:
    """Write one sample WAV per voice and its measurements."""
    SAMPLES.mkdir(parents=True, exist_ok=True)
    CHECKS.mkdir(parents=True, exist_ok=True)
    for vid in voice_ids:
        voice = get_voice(vid)
        f0s: list[float] = []
        embs: list[list[float]] = []
        for n, text in enumerate(SENTENCES):
            out = SAMPLES / f"{vid}.wav" if n == 0 else CHECKS / f"{vid}-{n}.wav"
            audio = engine.synthesize(text, voice, seed=1234 + n)
            encode(audio, engine.sample_rate, voice.pitch, out)
            wav16k = decode(out)
            f0s.append(_median_f0(wav16k))
            if n < 2:  # two sentences give the intra-voice distance
                embs.append(engine.speaker_embedding(wav16k).tolist())
        record = {"id": vid, "f0": f0s, "emb": embs}
        (CHECKS / f"{vid}.json").write_text(json.dumps(record))
        shown = "/".join(f"{f:.1f}" for f in f0s)
        print(f"{vid}: F0 {shown} Hz -> {SAMPLES / f'{vid}.wav'}")


def load_records(root: Path = CHECKS) -> list[Record]:
    """Measurements for every bank voice that has been rendered."""
    records: list[Record] = []
    for voice in BANK:
        path = root / f"{voice.id}.json"
        if path.is_file():
            raw = json.loads(path.read_text())
            a, b = (np.array(e, dtype=np.float32) for e in raw["emb"])
            records.append(Record(raw["id"], tuple(raw["f0"]), a, b))
    return records


def rtf(engine: ChatterboxEngine) -> None:
    """Render the five lines; print real-time factor and VRAM peaks."""
    import torch  # noqa: PLC0415

    engine.synthesize("Rozgrzewka.", get_voice("m1"), 0)  # warm-up, not timed
    torch.cuda.reset_peak_memory_stats()
    synth = audio_s = 0.0
    for vid, text in RTF_LINES:
        start = time.perf_counter()
        audio = engine.synthesize(text, get_voice(vid), 7)
        synth += time.perf_counter() - start
        audio_s += len(audio) / engine.sample_rate
    gib = 2**30
    print(
        f"lines={len(RTF_LINES)} audio={audio_s:.1f}s synth={synth:.1f}s "
        f"RTF={synth / audio_s:.2f} "
        f"vram_peak_allocated={torch.cuda.max_memory_allocated() / gib:.2f}GiB "
        f"vram_peak_reserved={torch.cuda.max_memory_reserved() / gib:.2f}GiB"
    )


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("what", choices=["render", "report", "rtf"])
    parser.add_argument("voices", nargs="*")
    args = parser.parse_args(argv)
    if args.what == "report":
        rows = distinctness(load_records())
        print(format_rows(rows))
        return 0 if len(rows) == len(BANK) and all(r.distinct for r in rows) else 1
    engine = ChatterboxEngine()
    if args.what == "render":
        render(engine, args.voices or [v.id for v in BANK])
    else:
        rtf(engine)
    return 0


if __name__ == "__main__":
    sys.exit(main())
