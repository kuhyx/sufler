"""End-to-end sealing of what the relay carries (DOCS-relay.md "E2E").

A request and a result are each one *unit*: the fields holding text
(``payload``; ``text``, ``audioB64``, ``error``) go into one ``_e2e`` blob,
crdt_sync's ``E2eCipher`` bound to the record's path (``sufler/requests/{rid}``,
``sufler/results/{rid}``), under the Argon2id key of the shared crdt-sync
passphrase. Ids, ``kind``, ``deviceId``, ``ok`` and the server times stay
clear, as do presence and clients. No new prefix and no copy: the data lives
seconds. A record without ``_e2e`` is read as stored (an older phone).

This PC creates the header (``sufler/e2e``) on first use; phones only read
it. The twin of ``lib/assist/relay_seal.dart``;
``test/assist/relay_e2e_vectors.json`` pins both.
"""

from __future__ import annotations

import base64
import hmac
import json
import logging
import os
from pathlib import Path
from typing import Any, Final, Protocol

from crdt_sync import (
    Argon2Params,
    E2eDecryptError,
    E2eHeaderError,
    E2eKey,
    E2eWrongPassphraseError,
    unlock_e2e,
)

from sufler_tts.relay.rtdb import ROOT, Db
from sufler_tts.relay.worker import RelayLocked

SEALED: Final = "_e2e"
HEADER: Final = "e2e"  # relative to ROOT: sufler/e2e
KEY_FILE: Final = "e2e-relay.key"
REQUEST_CLEAR: Final = frozenset({"kind", "deviceId", "ts"})
RESULT_CLEAR: Final = frozenset({"ok", "at"})
_KEY_LEN: Final = 32
_logger = logging.getLogger(__name__)


class Cipher(Protocol):
    """crdt_sync's ``E2eCipher``."""

    def seal(self, plaintext: str, *, path: str) -> str:
        """The blob of ``plaintext`` bound to ``path``."""
        ...

    def open(self, stored: str, *, path: str) -> str:
        """The plaintext of a blob sealed at ``path``."""
        ...


def _dumps(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


class Sealer:
    """Seals and opens relay records; paths are relative to :data:`ROOT`."""

    def __init__(self, cipher: Cipher) -> None:
        """Use ``cipher`` (the shared key's) for every record."""
        self._cipher = cipher

    def _seal(
        self, path: str, record: dict[str, Any], clear: frozenset[str]
    ) -> dict[str, Any]:
        secret = {k: v for k, v in record.items() if k not in clear}
        blob = self._cipher.seal(_dumps(secret), path=f"{ROOT}/{path}")
        return {**{k: v for k, v in record.items() if k in clear}, SEALED: blob}

    def seal_request(self, path: str, record: dict[str, Any]) -> dict[str, Any]:
        """``{kind, payload, deviceId, ts}`` as written to ``path``."""
        return self._seal(path, record, REQUEST_CLEAR)

    def seal_result(self, path: str, record: dict[str, Any]) -> dict[str, Any]:
        """``{ok, text | audioB64 | error, at}`` as written to ``path``."""
        return self._seal(path, record, RESULT_CLEAR)

    def open(self, path: str, stored: object) -> object:
        """``stored`` with its blob opened; unsealed records come back as is.

        A blob that does not open (tampered, moved, another key) is None.
        """
        if not isinstance(stored, dict) or not isinstance(stored.get(SEALED), str):
            return stored
        try:
            secret = json.loads(
                self._cipher.open(stored[SEALED], path=f"{ROOT}/{path}")
            )
        except E2eDecryptError, ValueError:
            _logger.warning("relay: %s does not open (another key?)", path)
            return None
        if not isinstance(secret, dict):
            return None
        return {**{k: v for k, v in stored.items() if k != SEALED}, **secret}


class _HeaderStore:
    """crdt_sync's ``RemoteStore``, just enough for ``unlock_e2e``.

    The header is one JSON string leaf, as the phone reads it.
    """

    def __init__(self, db: Db) -> None:
        self._db = db

    def list_directory(self, path: str) -> list[str]:
        """Nothing: only the header is read through here."""
        del path
        return []

    def get_file_text(self, path: str) -> str | None:
        """The header text; a non-string node comes back as JSON (bad header)."""
        value = self._db.get(path)
        return value if value is None or isinstance(value, str) else _dumps(value)

    def put_file_text(self, path: str, text: str, *, message: str) -> None:
        """Write the header as one string leaf."""
        del message
        self._db.put(path, text)

    def delete_file(self, path: str, *, message: str = "") -> None:
        """Refused: the header is never deleted."""
        del path, message
        msg = "the relay never deletes the e2e header"
        raise NotImplementedError(msg)

    def can_access_remote(self) -> bool:
        """Always: a failing call raises on its own."""
        return True


def _cached(state_dir: Path, store: _HeaderStore) -> E2eKey | None:
    """The key cached in ``state_dir`` if it still matches the header."""
    try:
        master = (state_dir / KEY_FILE).read_bytes()
        header = json.loads(store.get_file_text(HEADER) or "null")
        salt, check = base64.b64decode(header["salt"]), str(header["check"])
    except OSError, ValueError, TypeError, KeyError:
        return None
    if len(master) != _KEY_LEN:
        return None
    key = E2eKey.from_bytes(master)
    return key if hmac.compare_digest(key.check_for(salt), check) else None


def _remember(state_dir: Path, key: E2eKey) -> None:
    """Cache the derived key (0600) so a restart skips Argon2id."""
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / KEY_FILE
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(key.master)
    path.chmod(0o600)


def unlock(
    db: Db,
    passphrase: str,
    state_dir: Path | None = None,
    params: Argon2Params | None = None,
) -> Sealer:
    """The relay's sealer; creates the header at ``sufler/e2e`` on first use.

    Raises:
        RelayLocked: No passphrase, a wrong one, or an unreadable header.

    """
    store = _HeaderStore(db)
    key = _cached(state_dir, store) if state_dir is not None else None
    if key is None:
        if not passphrase:
            msg = "no crdt-sync passphrase on this PC"
            raise RelayLocked(msg)
        try:
            key = unlock_e2e(
                store,
                path_prefix=ROOT,
                passphrase=passphrase,
                params=params,
                e2e_path=HEADER,
            )
        except (E2eWrongPassphraseError, E2eHeaderError) as exc:
            raise RelayLocked(str(exc) or type(exc).__name__) from exc
        if state_dir is not None:
            _remember(state_dir, key)
    return Sealer(key.cipher())
