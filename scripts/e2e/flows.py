"""Core desktop flows F1-F5 (DOCS-features.md), one per invocation.

Usage (normally via scripts/e2e_desktop.sh F<n>, after `up`):
    flows.py F<n> --port 9479 --out private/e2e --pdf private/krasnale.pdf

Prints ``F<n> step i/total: ...`` before each step; on failure prints
``FAIL F<n> step i/total: <step> -> <why>; shot: <png>`` and exits 1.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

import oracle
from cdp import Cdp, CdpError
from flow_steps import f1_import, f2_roles, f3_rehearse, f4_anki, f5_voices

Json = dict[str, Any]
WOLF = "piaskowy-wilk"


class FlowError(Exception):
    """A flow step saw something other than what it expected."""


class Run:
    """One flow run: the CDP connection, numbered steps, artefact directory."""

    def __init__(self, flow: str, cdp: Cdp, out: Path, pdf: Path, total: int) -> None:
        """Artefacts go to ``out/<flow>/<timestamp>/``."""
        self.flow, self.cdp, self.pdf, self.total = flow, cdp, pdf, total
        self.dir = out / flow / time.strftime("%Y%m%d-%H%M%S")
        self.dir.mkdir(parents=True, exist_ok=True)
        self.index, self.what = 0, ""
        self.display = ":79"
        self.evidence: list[str] = []

    def step(self, what: str) -> None:
        """Log the next step before it runs (so the failing one is last)."""
        self.index += 1
        self.what = what
        print(f"{self.flow} step {self.index}/{self.total}: {what}", flush=True)

    def check(self, ok: object, why: str) -> None:
        """Fail the current step with ``why`` unless ``ok``."""
        if not ok:
            raise FlowError(why)

    def note(self, fact: str) -> None:
        """Record a piece of evidence for the PASS line."""
        print(f"  {fact}", flush=True)
        self.evidence.append(fact)

    def shot(self, name: str) -> Path:
        """Full-resolution X screenshot of the nested display (CDP's own
        capture comes back at half size under software rendering)."""
        out = self.dir / f"{name}.png"
        env = {**os.environ, "DISPLAY": self.display}
        done = subprocess.run(
            ["import", "-window", "root", str(out)], env=env, check=False, timeout=15
        )
        return out if done.returncode == 0 else self.cdp.screenshot(out)

    # --- shared navigation -------------------------------------------------

    def boot(self) -> None:
        """Reload the app (audio probe injected) on the library screen."""
        self.cdp.reload_instrumented()
        self.cdp.enable_semantics()
        self.cdp.wait_for("Twoje skrypty", 20)

    def stored(self) -> Json | None:
        """The script imported from the PDF, as stored in IndexedDB."""
        got = self.cdp.helper(f"script({json.dumps(self.pdf.name)})", wait=True)
        return got if isinstance(got, dict) else None

    def open_script(self) -> tuple[Json, oracle.RoleFacts]:
        """Open the imported script; returns it and the Wolf facts."""
        script = self.stored()
        self.check(script, f"{self.pdf.name} not in the library; run F1 first")
        assert script is not None  # for the type checker
        self.cdp.tap(script["title"], 15)
        self.cdp.wait_for("Twoje role", 15)
        return script, oracle.role_facts(script, WOLF)

    def chip(self, facts: oracle.RoleFacts) -> Json:
        """The Wolf role chip: ``<name> (<count>)``."""
        return self.cdp.wait_for(f"{facts.name} (", 10)

    def select_only_wolf(self, facts: oracle.RoleFacts) -> None:
        """Make the Wolf chip the one selected role."""
        for _ in range(3):
            hit = self.chip(facts)
            if hit["checked"] == "true":
                return
            self.cdp.click(hit)
            self.cdp.page.pump(0.5)
        self.check(False, f"chip {facts.name} would not select")

    def header(self) -> tuple[int, int] | None:
        """Rehearsal header ``kwestia <n>/<m>``, if shown."""
        found = re.search(r"kwestia (\d+)/(\d+)", self.cdp.text())
        return (int(found[1]), int(found[2])) if found else None


FLOWS: dict[str, tuple[int, Callable[[Run], None]]] = {
    "F1": (6, f1_import),
    "F2": (4, f2_roles),
    "F3": (8, f3_rehearse),
    "F4": (5, f4_anki),
    "F5": (4, f5_voices),
}


def main() -> int:
    """Run one flow; exit code 0 pass, 1 fail."""
    ap = argparse.ArgumentParser()
    ap.add_argument("flow", choices=sorted(FLOWS))
    ap.add_argument("--port", type=int, default=9479)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--pdf", type=Path, required=True)
    ap.add_argument("--display", default=":79")
    args = ap.parse_args()
    total, body = FLOWS[args.flow]
    cdp = Cdp(args.port)
    run = Run(args.flow, cdp, args.out.resolve(), args.pdf.resolve(), total)
    run.display = args.display
    try:
        body(run)
    except (FlowError, CdpError, TimeoutError) as e:
        shot = run.shot("fail")
        print(
            f"FAIL {run.flow} step {run.index}/{total}: {run.what} -> {e}; shot: {shot}"
        )
        return 1
    finally:
        cdp.close()
    print(f"PASS {run.flow}: {'; '.join(run.evidence)}; artefacts: {run.dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
