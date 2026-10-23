"""Print the notes of an Anki .apkg as JSON: ``[[front, back], ...]``.

Run as ``python3 -I apkg_check.py <deck.apkg>`` (isolated: the archive is a
downloaded, untrusted file). Unpacks ``collection.anki2`` into a temporary
directory and reads ``notes.flds`` (fields joined by U+001F) with sqlite3.
"""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path


def notes(apkg: Path) -> list[list[str]]:
    """Every note's fields, in note-id order."""
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(apkg) as archive:
            names = set(archive.namelist())
            if "collection.anki2" not in names or "media" not in names:
                msg = f"not an apkg (entries: {sorted(names)})"
                raise SystemExit(msg)
            db = Path(archive.extract("collection.anki2", tmp))
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            rows = con.execute("SELECT flds FROM notes ORDER BY id").fetchall()
        finally:
            con.close()
    return [str(flds).split("\x1f") for (flds,) in rows]


def main() -> None:
    """Entry point: one argument, the .apkg path."""
    if len(sys.argv) != 2:
        raise SystemExit("usage: apkg_check.py <deck.apkg>")
    json.dump(notes(Path(sys.argv[1])), sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
