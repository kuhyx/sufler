"""Chatterbox Multilingual on CUDA. Imported only inside the engine child."""

from __future__ import annotations

import importlib

import numpy as np
import torch

from sufler_tts.assets import WEIGHTS, prompt_path
from sufler_tts.compat import install_pkg_resources_shim
from sufler_tts.engine import SAMPLE_RATE, Audio, chatterbox_name
from sufler_tts.voices import Voice

LANGUAGE = "pl"


class ChatterboxEngine:
    """Loads the model on construction; one set of conditionals per voice base."""

    def __init__(self, device: str = "cuda") -> None:
        """Load the pinned weights directory (fetched by install_tts.sh)."""
        install_pkg_resources_shim()  # must precede the chatterbox import
        # import_module: chatterbox ships no type information.
        mtl = importlib.import_module("chatterbox.mtl_tts")
        self.device = device
        if not (WEIGHTS / "t3_mtl23ls_v2.safetensors").is_file():
            raise FileNotFoundError(f"no Chatterbox weights in {WEIGHTS}")
        # from_local, not from_pretrained: no Hugging Face hub lookup at runtime.
        self.model = mtl.ChatterboxMultilingualTTS.from_local(WEIGHTS, device)
        self._conds: dict[str, object] = {"default": self.model.conds}

    @property
    def name(self) -> str:
        """`chatterbox-multilingual@<installed version>`."""
        return chatterbox_name()

    @property
    def sample_rate(self) -> int:
        """S3Gen output rate."""
        return SAMPLE_RATE

    def _use_base(self, voice: Voice) -> None:
        if voice.base not in self._conds:
            path = prompt_path(voice.base)
            if path is None or not path.is_file():
                raise FileNotFoundError(f"no synthetic prompt for {voice.base}")
            self.model.prepare_conditionals(str(path), voice.exaggeration)
            self._conds[voice.base] = self.model.conds
        self.model.conds = self._conds[voice.base]

    def synthesize(self, text: str, voice: Voice, seed: int) -> Audio:
        """One generation, seeded so a re-render reproduces the clip."""
        self._use_base(voice)
        torch.manual_seed(seed)
        wav = self.model.generate(
            text,
            LANGUAGE,
            exaggeration=voice.exaggeration,
            cfg_weight=voice.cfg_weight,
            temperature=voice.temperature,
        )
        return np.asarray(wav.squeeze(0).cpu().numpy(), dtype=np.float32)

    def speaker_embedding(self, wav16k: Audio) -> Audio:
        """Chatterbox's voice-encoder embedding (unit norm) of 16 kHz audio."""
        emb = self.model.ve.embeds_from_wavs([wav16k], sample_rate=16_000)
        return np.asarray(emb[0], dtype=np.float32)

    def close(self) -> None:
        """Drop the model; the process exit then frees the CUDA context."""
        self._conds.clear()
        del self.model
        torch.cuda.empty_cache()
