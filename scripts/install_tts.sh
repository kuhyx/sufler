#!/bin/bash

# ============================================================================
# Install the sufler voice service (tts/): Python 3.14 venv from uv.lock,
# Chatterbox Multilingual weights, Polish Piper voices and the synthetic voice
# prompts built from them, then links systemd/sufler-tts.service into the
# systemd --user unit dir and reloads it. Idempotent: re-running only fills
# what is missing; downloads resume and are sha256-verified. User-level only.
# Does NOT enable/start the unit:
#   systemctl --user enable --now sufler-tts.service
# Needs: uv, ffmpeg (libopus + rubberband), piper; installs the missing ones.
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly TTS="$ROOT/tts"
readonly UNIT="sufler-tts.service"
readonly UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
export PATH="$HOME/.local/bin:$PATH"

log() { printf '[install_tts] %s\n' "$*"; }
die() { printf '[install_tts] error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ensure_uv() {
    have uv && return
    log "installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    have uv || die "uv still missing after install"
}

ensure_ffmpeg() {
    local encoders filters
    if ! have ffmpeg; then
        log "installing ffmpeg"
        sudo -n pacman -S --needed --noconfirm ffmpeg ||
            die "run: sudo pacman -S --needed ffmpeg"
    fi
    encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
    filters="$(ffmpeg -hide_banner -filters 2>/dev/null)"
    grep -q libopus <<<"$encoders" || die "ffmpeg lacks the libopus encoder"
    grep -q rubberband <<<"$filters" || die "ffmpeg lacks the rubberband filter"
}

ensure_piper() {
    have piper && return
    log "installing piper-tts"
    uv tool install piper-tts
    have piper || die "piper still missing after install"
}

python_step() {
    # Run a sufler_tts module from tts/ (it is not an installed package).
    (cd "$TTS" && .venv/bin/python -m "$@")
}

install_unit() {
    # The unit hard-codes %h/src/sufler; refuse to link a checkout elsewhere.
    [[ "$ROOT" == "$HOME/src/sufler" ]] ||
        die "unit expects the repo at ~/src/sufler, not $ROOT"
    mkdir -p "$UNIT_DIR"
    ln -sfn "$ROOT/systemd/$UNIT" "$UNIT_DIR/$UNIT"
    systemctl --user daemon-reload
}

main() {
    ensure_uv
    ensure_ffmpeg
    ensure_piper
    log "syncing venv from uv.lock"
    uv sync --locked --directory "$TTS"
    log "fetching Chatterbox weights (~3.2 GB on first run; resumes)"
    python_step sufler_tts.fetch_assets weights
    log "fetching Polish Piper voices"
    python_step sufler_tts.fetch_assets piper
    log "building synthetic voice prompts"
    python_step sufler_tts.fetch_assets prompts
    log "linking $UNIT into $UNIT_DIR"
    install_unit
    log "done; start it with: systemctl --user enable --now $UNIT"
}

main "$@"
