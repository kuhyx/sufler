"""faster-whisper large-v3-turbo (CPU int8; CUDA 12 when present). STT child only."""

from __future__ import annotations

import ctypes
import importlib
import importlib.util
from pathlib import Path

from sufler_tts.assets import WHISPER_DIR
from sufler_tts.engine import Audio
from sufler_tts.transcribe import Segment, Transcript, Word, whisper_name

BEAM_SIZE = 2
# Silero VAD (bundled with faster-whisper) drops silence before decoding,
# which is what stops Whisper inventing text for a quiet room. Lines are
# separated by short pauses, so cut at 500 ms rather than the 2 s default.
VAD = {"min_silence_duration_ms": 500, "speech_pad_ms": 150}


def preload_cublas12() -> bool:
    """Make libcublas.so.12 loadable; True when it is.

    ctranslate2 wheels are built for CUDA 12, and the project ships no nvidia
    wheels (FOSS: torch is the CPU build). A cu12 cuBLAS comes from an
    `nvidia-cublas-cu12` wheel installed by hand (loaded by absolute path, so
    ctranslate2's own dlopen finds it already mapped) or a system CUDA 12.
    """
    names = ("libcublasLt.so.12", "libcublas.so.12")
    try:
        spec = importlib.util.find_spec("nvidia.cublas")
    except ModuleNotFoundError:  # no `nvidia` namespace package at all
        spec = None
    if spec is not None and spec.submodule_search_locations:
        lib = Path(next(iter(spec.submodule_search_locations))) / "lib"
        paths = [str(lib / name) for name in names]
    else:
        paths = list(names)
    try:
        for path in paths:
            ctypes.CDLL(path, mode=ctypes.RTLD_GLOBAL)
    except OSError:
        return False
    return True


def default_device() -> str:
    """Pick `cuda` only with a cu12 cuBLAS AND a visible GPU, else `cpu`.

    ctranslate2 counts GPUs through the driver even when cuBLAS 12 is
    missing, so the count alone would pick a device that fails on first use.
    """
    if not preload_cublas12():
        return "cpu"
    ct2 = importlib.import_module("ctranslate2")
    return "cuda" if ct2.get_cuda_device_count() > 0 else "cpu"


class WhisperTranscriber:
    """Loads the pinned CT2 weights on construction (fetched by fetch_assets)."""

    def __init__(self, device: str | None = None) -> None:
        """Load the weights from `assets.WHISPER_DIR` (fp16 on GPU, int8 on CPU)."""
        if not (WHISPER_DIR / "model.bin").is_file():
            raise FileNotFoundError(f"no Whisper weights in {WHISPER_DIR}")
        device = device or default_device()
        compute = "float16" if device == "cuda" else "int8"
        if device == "cuda":
            preload_cublas12()  # an explicit "cuda" skipped default_device()
        # import_module: faster-whisper ships no type information.
        whisper = importlib.import_module("faster_whisper")
        self.model = whisper.WhisperModel(
            str(WHISPER_DIR), device=device, compute_type=compute
        )

    @property
    def name(self) -> str:
        """`faster-whisper@<ver>/large-v3-turbo`."""
        return whisper_name()

    def transcribe(self, audio: Audio, language: str) -> Transcript:
        """Transcribe 16 kHz mono samples; bounds come from word timestamps.

        The words themselves go out too: the app cuts a whole sung or spoken
        run into its lines by them.

        Segment times are coarse (whole decoding windows); the first word's
        start and the last word's end track the voice far more tightly, and
        they are what the app uses to cut a line.
        """
        segments, _ = self.model.transcribe(
            audio,
            language=language,
            beam_size=BEAM_SIZE,
            vad_filter=True,
            vad_parameters=VAD,
            word_timestamps=True,
            condition_on_previous_text=False,
        )
        out: list[Segment] = []
        words: list[Word] = []
        starts: list[float] = []
        ends: list[float] = []
        for seg in segments:
            text = seg.text.strip()
            if not text:
                continue
            out.append(Segment(round(seg.start, 2), round(seg.end, 2), text))
            if seg.words:
                starts.append(seg.words[0].start)
                ends.append(seg.words[-1].end)
                words.extend(
                    Word(round(w.start, 2), round(w.end, 2), w.word.strip())
                    for w in seg.words
                )
        if not out:
            return Transcript("", [], None, None, self.name)
        text = " ".join(s.text for s in out)
        start = round(starts[0] if starts else out[0].start, 2)
        end = round(ends[-1] if ends else out[-1].end, 2)
        return Transcript(text, out, start, end, self.name, words)

    def close(self) -> None:
        """Drop the model; the process exit then frees any CUDA context."""
        del self.model
