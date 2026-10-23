"""Where the relay connects, as whom, and the threads that keep it running.

The database URL and API key come from crdt-sync's shared
`~/.config/crdt-sync/firebase.json`; the signed-in session is sufler's own,
`~/.config/sufler/firebase_auth.json`, seeded once with crdt-sync
`python3 -m tool.seed_session ... --app sufler` (tutor's `relay/config.py`
pattern; never `firebase_client_for`, which falls back to the dead shared
password). No config or no session: the relay logs why and the service
serves HTTP only.
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Final

from crdt_sync import (
    ConfigError,
    FileCredentialStore,
    FirebaseAuthError,
    FirebaseConfig,
    FirebaseTokenProvider,
    credential_store_for,
    load_device_identity,
)

from sufler_tts.assets import DATA
from sufler_tts.relay.rtdb import Rtdb, RtdbError
from sufler_tts.relay.worker import BEAT_S, GC_S, RESCAN_S, AssistLike, Relay

APP: Final = "sufler"
_logger = logging.getLogger(__name__)


class RelaySetupError(RuntimeError):
    """The relay cannot start: no config or no signed-in session."""


def connect(config: Path | None = None, auth: Path | None = None) -> Rtdb:
    """Sufler's RTDB client, signed in as the `sufler` app."""
    try:
        cfg = FirebaseConfig.load(config)
    except ConfigError as err:
        raise RelaySetupError(f"no crdt-sync firebase config: {err}") from None
    store = FileCredentialStore(auth) if auth else credential_store_for(APP)
    provider = FirebaseTokenProvider(cfg.api_key, store)
    if not provider.has_session():
        raise RelaySetupError(
            "no signed-in session in ~/.config/sufler/firebase_auth.json; seed "
            "it in ~/src/utils/crdt-sync: python3 -m tool.seed_session "
            "--client-id ... --client-secret ... --app sufler"
        )

    def token() -> str:
        try:
            return str(provider.id_token())
        except FirebaseAuthError as err:
            raise RtdbError(f"firebase auth failed: {err}") from None

    return Rtdb(cfg.database_url, token)


def device_id(data_dir: Path = DATA) -> str:
    """The PC's persisted uuid4 (`<data>/device_id`, the crdt_sync format)."""
    return str(load_device_identity(data_dir / "device_id").device_id)


def _every(stop: threading.Event, seconds: float, step: Callable[[], object]) -> None:
    while not stop.is_set():
        try:
            step()
        except RtdbError as err:
            _logger.warning("relay: %s", err)
        stop.wait(seconds)


def _listen(stop: threading.Event, relay: Relay, db: Rtdb) -> None:
    backoff = 1.0
    while not stop.is_set():
        try:
            relay.on_events(db.stream("requests"))
            backoff = 1.0
        except RtdbError as err:
            _logger.warning("relay stream: %s (retry in %.0f s)", err, backoff)
            stop.wait(backoff)
            backoff = min(backoff * 2, 30.0)


class RelayHandle:
    """The running relay: daemon threads plus a clean `stop()`."""

    def __init__(self, relay: Relay, db: Rtdb) -> None:
        """Start the beat, rescan, GC and stream threads."""
        self.relay, self.stop_event = relay, threading.Event()
        jobs: list[tuple[Callable[..., None], tuple[object, ...]]] = [
            (_every, (self.stop_event, BEAT_S, relay.beat)),
            (_every, (self.stop_event, RESCAN_S, relay.scan)),
            (_every, (self.stop_event, GC_S, relay.gc)),
            (_listen, (self.stop_event, relay, db)),
        ]
        for target, args in jobs:
            threading.Thread(target=target, args=args, daemon=True).start()

    def stop(self) -> None:
        """Stop the loops and remove the presence beat."""
        self.stop_event.set()
        try:
            self.relay.leave()
        except RtdbError as err:
            _logger.warning("relay leave: %s", err)


def start(
    assist: AssistLike,
    env: Mapping[str, str],
    connect: Callable[[], Rtdb] = connect,
) -> RelayHandle | None:
    """Start the relay unless `SUFLER_RELAY=0`; None when it cannot run."""
    if env.get("SUFLER_RELAY", "1") == "0":
        return None
    try:
        db = connect()
        relay = Relay(db, assist, device_id(), clock=time.time)
    except RelaySetupError as err:
        _logger.warning("relay off: %s (HTTP only)", err)
        return None
    return RelayHandle(relay, db)
