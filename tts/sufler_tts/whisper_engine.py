"""faster-whisper large-v3-turbo on CUDA. Imported only inside the STT child."""

from __future__ import annotations

import ctypes
import importlib
import importlib.util
from pathlib import Path

from sufler_tts.assets import WHISPER_DIR
from sufler_tts.engine import Audio
from sufler_tts.transcribe import Segment, Transcript, whisper_name

BEAM_SIZE = 2
# Silero VAD (bundled with faster-whisper) drops silence before decoding,
# which is what stops Whisper inventing text for a quiet room. Lines are
# separated by short pauses, so cut at 500 ms rather than the 2 s default.
VAD = {"min_silence_duration_ms": 500, "speech_pad_ms": 150}


def preload_cublas12() -> None:
    """Make libcublas.so.12 loadable: ctranslate2 wheels are built for CUDA 12.

    torch (Chatterbox) brings CUDA 13 and Arch's /opt/cuda is 13 too, so the
    cu12 runtime comes from the pinned `nvidia-cublas-cu12` wheel. Loading it
    by absolute path first lets ctranslate2's own dlopen("libcublas.so.12")
    find the already-mapped library, with no LD_LIBRARY_PATH in the unit.
    """
    spec = importlib.util.find_spec("nvidia.cublas")
    if spec is None or not spec.submodule_search_locations:
        return  # CPU-only box or a system CUDA 12: let ctranslate2 try
    lib = Path(next(iter(spec.submodule_search_locations))) / "lib"
    for name in ("libcublasLt.so.12", "libcublas.so.12"):
        ctypes.CDLL(str(lib / name), mode=ctypes.RTLD_GLOBAL)


class WhisperTranscriber:
    """Loads the pinned CT2 weights on construction (fetched by fetch_assets)."""

    def __init__(self, device: str = "cuda") -> None:
        """Load fp16 weights from `assets.WHISPER_DIR`; no hub lookup."""
        if not (WHISPER_DIR / "model.bin").is_file():
            raise FileNotFoundError(f"no Whisper weights in {WHISPER_DIR}")
        compute = "float16" if device == "cuda" else "int8"
        preload_cublas12()
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
        if not out:
            return Transcript("", [], None, None, self.name)
        text = " ".join(s.text for s in out)
        start = round(starts[0] if starts else out[0].start, 2)
        end = round(ends[-1] if ends else out[-1].end, 2)
        return Transcript(text, out, start, end, self.name)

    def close(self) -> None:
        """Drop the model; the process exit then frees the CUDA context."""
        del self.model
