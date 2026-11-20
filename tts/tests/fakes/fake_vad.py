"""Stand-in for `whisper-vad-speech-segments`: prints $FAKE_VAD_SPANS.

`FAKE_VAD_SPANS="1.5-4.0;6.0-7.25"` (seconds) prints the lines the real tool
prints, in centiseconds; empty means no speech.
"""

from __future__ import annotations

import os

spans = [s for s in os.environ.get("FAKE_VAD_SPANS", "").split(";") if s]
print(f"Detected {len(spans)} speech segments:")
for i, span in enumerate(spans):
    start, end = (float(x) * 100 for x in span.split("-"))
    print(f"Speech segment {i}: start = {start:.2f}, end = {end:.2f}")
