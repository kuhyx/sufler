"""POST /transcribe over the fake transcriber; decoding uses the real ffmpeg."""

from __future__ import annotations

import json
import subprocess
import threading
import urllib.error
import urllib.request
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import numpy as np
import pytest

from sufler_tts.cache import ClipCache
from sufler_tts.engine import FakeEngine
from sufler_tts.jobs import JobRunner
from sufler_tts.process_stt import ProcessTranscriber
from sufler_tts.server import make_server, parse_language
from sufler_tts.transcribe import (
    STT_RATE,
    FakeTranscriber,
    decode_audio,
)


def _clip(tmp_path: Path, fmt: str, *, rate: int = 16_000, loud: bool = True) -> bytes:
    """A 2 s clip: 0.5 s silence, then 1 s of a 440 Hz sine (or all silence)."""
    src = (
        "aevalsrc='if(between(t,0.5,1.5),0.5*sin(2*PI*440*t),0)':d=2"
        if loud
        else "anullsrc=r=16000:cl=mono"
    )
    codec = {"wav": [], "ogg": ["-c:a", "libopus"], "webm": ["-c:a", "libopus"]}[fmt]
    out = tmp_path / f"clip.{fmt}"
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi"]
    cmd += ["-i", src, "-t", "2", "-ac", "1", "-ar", str(rate), *codec, str(out)]
    subprocess.run(cmd, check=True, capture_output=True)
    return out.read_bytes()


@pytest.fixture
def stt() -> FakeTranscriber:
    return FakeTranscriber()


@pytest.fixture
def url(stt: FakeTranscriber, cache: ClipCache, tmp_path: Path) -> Iterator[str]:
    runner = JobRunner(FakeEngine(), cache, tmp_path / "packs")
    server = make_server(runner, port=0, gpu=lambda: None, transcriber=stt)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    host, port = server.server_address[:2]
    yield f"http://{host!s}:{port}"
    server.shutdown()
    runner.stop()


def _post(url: str, body: bytes) -> tuple[int, Any]:
    req = urllib.request.Request(url, body, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read())


def test_response_shape(url: str, tmp_path: Path) -> None:
    status, body = _post(f"{url}/transcribe?lang=pl", _clip(tmp_path, "wav"))
    assert status == 200
    assert set(body) == {
        "text", "segments", "words", "speechStart", "speechEnd", "engine"
    }  # fmt: skip
    assert body["engine"] == "fake-stt@1"
    assert body["text"] == "fake pl"
    assert set(body["segments"][0]) == {"start", "end", "text"}
    # word times (what the app cuts a whole song or monologue by)
    words = body["words"]
    assert [w["word"] for w in words] == ["fake", "pl"]
    assert set(words[0]) == {"start", "end", "word"}
    assert words[0]["start"] == body["speechStart"]
    assert words[-1]["end"] == body["speechEnd"]
    assert body["speechStart"] == pytest.approx(0.5, abs=0.05)
    assert body["speechEnd"] == pytest.approx(1.5, abs=0.05)


@pytest.mark.parametrize("fmt", ["wav", "ogg", "webm"])
def test_formats_are_decoded_via_ffmpeg(
    url: str, stt: FakeTranscriber, tmp_path: Path, fmt: str
) -> None:
    status, body = _post(f"{url}/transcribe", _clip(tmp_path, fmt))
    assert status == 200
    assert body["speechStart"] == pytest.approx(0.5, abs=0.1)
    assert body["speechEnd"] == pytest.approx(1.5, abs=0.1)
    # whatever the container, the model gets mono 16 kHz (2 s here)
    assert stt.calls[-1][0] == pytest.approx(2 * STT_RATE, abs=1600)
    assert stt.calls[-1][1] == "pl"  # default language


def test_any_sample_rate_is_resampled(
    url: str, stt: FakeTranscriber, tmp_path: Path
) -> None:
    status, _ = _post(f"{url}/transcribe", _clip(tmp_path, "wav", rate=44_100))
    assert status == 200
    assert stt.calls[-1][0] == pytest.approx(2 * STT_RATE, abs=1600)


def test_silence_has_no_speech_bounds(url: str, tmp_path: Path) -> None:
    status, body = _post(f"{url}/transcribe", _clip(tmp_path, "wav", loud=False))
    assert status == 200
    assert body["text"] == ""
    assert body["segments"] == []
    assert body["words"] == []
    assert body["speechStart"] is None
    assert body["speechEnd"] is None


@pytest.mark.parametrize("body", [b"", b"definitely not audio" * 50])
def test_garbage_is_400(url: str, body: bytes) -> None:
    status, err = _post(f"{url}/transcribe", body)
    assert status == 400
    assert "audio" in err["error"]


def test_bad_lang_is_400(url: str, tmp_path: Path) -> None:
    status, err = _post(f"{url}/transcribe?lang=../x", _clip(tmp_path, "wav"))
    assert status == 400
    assert "lang" in err["error"]


def test_model_failure_is_500(url: str, stt: FakeTranscriber, tmp_path: Path) -> None:
    stt.fail = True
    status, err = _post(f"{url}/transcribe", _clip(tmp_path, "wav"))
    assert status == 500
    assert "fake transcriber failure" in err["error"]


def test_health_names_the_stt_model(url: str) -> None:
    with urllib.request.urlopen(f"{url}/health", timeout=5) as r:
        assert json.loads(r.read())["stt"] == "fake-stt@1"


def test_without_transcriber_is_503(cache: ClipCache, tmp_path: Path) -> None:
    runner = JobRunner(FakeEngine(), cache, tmp_path / "packs")
    server = make_server(runner, port=0, gpu=lambda: None)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    host, port = server.server_address[:2]
    try:
        assert _post(f"http://{host!s}:{port}/transcribe", b"x")[0] == 503
    finally:
        server.shutdown()
        runner.stop()


def test_parse_language() -> None:
    assert parse_language("") == "pl"
    assert parse_language("lang=EN") == "en"
    with pytest.raises(ValueError, match="lang"):
        parse_language("lang=polish-ish")


def test_decode_audio_rejects_garbage() -> None:
    with pytest.raises(ValueError, match="undecodable"):
        decode_audio(b"nope")


FAKE_STT = "sufler_tts.transcribe:FakeTranscriber"


def test_process_transcriber_lazy_child_and_idle_unload(tmp_path: Path) -> None:
    stt = ProcessTranscriber(FAKE_STT, "fake-stt@1", idle_s=0.0, watch_every=None)
    assert not stt.loaded
    audio = decode_audio(_clip(tmp_path, "wav"))
    result = stt.transcribe(audio, "pl")
    assert stt.loaded
    assert result.text == "fake pl"
    assert result.speech_start == pytest.approx(0.5, abs=0.05)
    assert stt.reaper.check()
    assert not stt.loaded
    stt.transcribe(audio, "en")  # reloads
    assert stt.loaded
    stt.close()
    assert not stt.loaded


def test_process_transcriber_load_error_is_raised() -> None:
    stt = ProcessTranscriber("sufler_tts.transcribe:Nope", "x", watch_every=None)
    with pytest.raises(RuntimeError, match="Nope"):
        stt.transcribe(np.zeros(1600, dtype=np.float32), "pl")
    assert not stt.loaded
