"""Core desktop flows F1-F7 (DOCS-features.md), one per invocation.

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
from flow_pack import f6_pack
from flow_rehearse import f3_rehearse
from flow_steps import f1_import, f2_roles, f4_anki, f5_voices
from flow_stt import f7_transcribe

Json = dict[str, Any]


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
        self.role = "zagiewka"
        self.pack = Path()
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
        """Reload the app (audio probe injected): it shows the library, or
        (once a script was opened) that script's hub straight away."""
        self.cdp.reload_instrumented()
        self.cdp.enable_semantics()
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if self.cdp.find("Twoje skrypty") or self.cdp.find("Moje role"):
                return
            self.cdp.page.pump(0.3)
        raise TimeoutError("neither the library nor a script hub after 20 s")

    def stored(self) -> Json | None:
        """The script imported from the PDF, as stored in IndexedDB."""
        got = self.cdp.helper(f"script({json.dumps(self.pdf.name)})", wait=True)
        return got if isinstance(got, dict) else None

    def open_script(self) -> tuple[Json, oracle.RoleFacts]:
        """Open the imported script; returns it and the role's facts."""
        script = self.stored()
        self.check(script, f"{self.pdf.name} not in the library; run F1 first")
        assert script is not None  # for the type checker
        if not self.cdp.find("Moje role"):
            self.cdp.tap(script["title"], 15)
        self.cdp.tap("Moje role", 15)
        self.cdp.wait_for("Twoje role", 15)
        return script, oracle.role_facts(script, self.role)

    def hub(self, tab: str = "Sceny") -> None:
        """Back from "Moje role" to the script hub, on ``tab``."""
        if self.cdp.find("Twoje role"):
            self.cdp.tap("Back")
        self.cdp.tap(tab, 10)

    def chip(self, facts: oracle.RoleFacts) -> Json:
        """The role chip: ``<name> (<count>)``."""
        return self.cdp.wait_for(f"{facts.name} (", 10)

    def select_only_role(self, facts: oracle.RoleFacts) -> None:
        """Make the role's chip the one selected role (deselect the rest),
        with exactly its own groups ticked, as a fresh pick of it would."""
        mine = self.chip(facts)["text"]
        for _ in range(6):
            on = self.cdp.helper("selectedChips()")
            on = on if isinstance(on, list) else []
            if on == [mine]:
                self._only_own_groups()
                return
            other = [t for t in on if t != mine]
            self.cdp.click(self.cdp.wait_for(other[0] if other else mine, 5))
            self.cdp.page.pump(0.5)
        self.check(False, f"could not make {mine!r} the only selected role")

    def _only_own_groups(self) -> None:
        """Tick the groups marked "twoja grupa", untick the rest.

        Unticking a character keeps the groups its pick pre-ticked (by design:
        "untick to drop them"), so a previous run's role leaves them behind.
        """
        for _ in range(8):
            boxes = self.cdp.helper("groupBoxes()")
            wrong = [
                b["text"]
                for b in (boxes if isinstance(boxes, list) else [])
                if b["checked"] != ("twoja grupa" in b["text"])
            ]
            if not wrong:
                return
            self.cdp.click(self.cdp.wait_for(wrong[0], 5))
            self.cdp.page.pump(0.5)
        self.check(False, "could not tick exactly the role's own groups")

    def picked_roles(self, script: Json) -> set[str]:
        """The roles the app saved in the script's prefs, checked against
        the data: the role plus the groups its pick pre-ticks ("Wszyscy", ...;
        :func:`oracle.own_groups`), which the app rehearses and exports too.
        """
        prefs = self.cdp.helper(
            f"json({json.dumps('prefs/' + script['id'])})", wait=True
        )
        roles = set(prefs.get("roles", [])) if isinstance(prefs, dict) else set()
        want = {f"character:{self.role}"} | oracle.own_groups(script, self.role)
        self.check(
            roles == want, f"prefs roles {sorted(roles)}, expected {sorted(want)}"
        )
        return want

    def header(self) -> tuple[int, int] | None:
        """Rehearsal header ``kwestia <n>/<m>``, if shown."""
        found = re.search(r"kwestia (\d+)/(\d+)", self.cdp.text())
        return (int(found[1]), int(found[2])) if found else None


FLOWS: dict[str, tuple[int, Callable[[Run], None]]] = {
    "F1": (6, f1_import),
    "F2": (4, f2_roles),
    "F3": (7, f3_rehearse),
    "F4": (5, f4_anki),
    "F5": (4, f5_voices),
    "F6": (6, f6_pack),
    "F7": (4, f7_transcribe),
}


def main() -> int:
    """Run one flow; exit code 0 pass, 1 fail."""
    ap = argparse.ArgumentParser()
    ap.add_argument("flow", choices=sorted(FLOWS))
    ap.add_argument("--port", type=int, default=9479)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--pdf", type=Path, required=True)
    ap.add_argument("--display", default=":79")
    ap.add_argument("--role", default="zagiewka", help="character id to play")
    ap.add_argument("--pack", type=Path, help="voice pack zip (F6, F7)")
    args = ap.parse_args()
    total, body = FLOWS[args.flow]
    cdp = Cdp(args.port)
    run = Run(args.flow, cdp, args.out.resolve(), args.pdf.resolve(), total)
    run.display = args.display
    run.role = args.role
    run.pack = (args.pack or args.pdf.with_suffix(".sufler-audio.zip")).resolve()
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
