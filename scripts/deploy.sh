#!/bin/bash

# ============================================================================
# Deploy sufler everywhere it runs, from the live checkout ~/src/sufler:
#   1. git pull --ff-only (the sufler-tts unit runs from that checkout), then
#      re-exec the pulled copy of this script so the pulled code is deployed.
#   2. desktop: packaging/install_arch.sh (web build + wrapper -> pacman pkg).
#   3. tts: link the unit if missing, uv sync the venv, restart it, wait
#      for /health ok.
#   4. phone: release build + `adb install -r` via phone_deploy.sh (never
#      uninstall, never pm clear), then check the new versionCode landed.
# Exits non-zero unless every health check passes. Idempotent.
#
# Usage: scripts/deploy.sh            full deploy
#        scripts/deploy.sh --health   health checks only (no pull, no build)
# Env:   SUFLER_LIVE_DIR (default ~/src/sufler), SUFLER_TTS_URL
#        (default http://127.0.0.1:8791), ADB_SERIAL (default the Pixel 6a).
# ============================================================================

set -euo pipefail

readonly LIVE="${SUFLER_LIVE_DIR:-$HOME/src/sufler}"
readonly TTS_URL="${SUFLER_TTS_URL:-http://127.0.0.1:8791}"
readonly UNIT="sufler-tts.service"
readonly UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
readonly APP_ID="com.kuhy.sufler"
readonly SERIAL="${ADB_SERIAL:-23181JEGR08034}"
readonly CAPPED="$HOME/.claude/scripts/capped.sh"
readonly PHONE_DEPLOY="$HOME/.claude/scripts/phone_deploy.sh"
# Chatterbox + faster-whisper load onto the GPU before /health answers.
readonly TTS_WAIT_SECS=180

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] FAIL: %s\n' "$*" >&2; exit 1; }

# Heavy builds go through the resource cap when this machine has it.
capped() {
    if [[ -x $CAPPED ]]; then
        CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"
    else
        "$@"
    fi
}

# pubspec 1.2.3+4 -> 1.2.3
pubspec_version() {
    grep -m1 '^version:' "$LIVE/pubspec.yaml" |
        sed -e 's/^version:[[:space:]]*//' -e 's/+.*//'
}

# Installed versionCode of the app on the phone; empty when not installed.
phone_version_code() {
    adb -s "$SERIAL" shell dumpsys package "$APP_ID" |
        sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1
}

phone_version_name() {
    adb -s "$SERIAL" shell dumpsys package "$APP_ID" |
        sed -n 's/.*versionName=\([^[:space:]]*\).*/\1/p' | head -1
}

update_checkout() {
    log "pull $LIVE"
    git -C "$LIVE" pull --ff-only
    if [[ ! -f $LIVE/lib/assist/firebase_local.dart ]]; then
        log "write firebase config"
        (cd "$LIVE" && dart run tool/write_firebase_config.dart)
    fi
}

check_desktop() {
    local want have
    want="$(pubspec_version)"
    have="$(pacman -Q sufler 2>/dev/null | awk '{print $2}')" ||
        die "desktop: package sufler not installed"
    [[ ${have%-*} == "$want" ]] ||
        die "desktop: pacman has sufler ${have:-none}, pubspec says $want"
    # The version alone does not move per commit: compare the bundle too.
    if [[ -f $LIVE/build/web/main.dart.js ]]; then
        cmp -s "$LIVE/build/web/main.dart.js" /opt/sufler/web/main.dart.js ||
            die "desktop: /opt/sufler/web differs from the fresh build"
    fi
    log "pass desktop (sufler $have)"
}

check_tts() {
    systemctl --user is-active --quiet "$UNIT" || die "tts: $UNIT not active"
    curl -sf -m 5 "$TTS_URL/health" | jq -e '.ok == true' >/dev/null ||
        die "tts: $TTS_URL/health is not ok"
    log "pass tts ($TTS_URL/health ok)"
}

check_phone() {
    local name
    adb -s "$SERIAL" get-state >/dev/null 2>&1 || die "phone: $SERIAL unreachable"
    name="$(phone_version_name)"
    [[ $name == "$(pubspec_version)" ]] ||
        die "phone: $APP_ID versionName=${name:-none}, pubspec says $(pubspec_version)"
    log "pass phone ($APP_ID $name, versionCode $(phone_version_code))"
}

deploy_desktop() {
    log "desktop: build + install package"
    capped "$LIVE/packaging/install_arch.sh"
    check_desktop
}

deploy_tts() {
    if [[ ! -e $UNIT_DIR/$UNIT ]]; then
        log "tts: install service"
        "$LIVE/scripts/install_tts.sh"
        systemctl --user enable "$UNIT"
    fi
    # A pin bump (e.g. crdt-sync for the relay's e2e) must reach the venv the
    # unit runs from, or the relay stays off after the restart.
    log "tts: sync venv from uv.lock"
    uv sync --locked --directory "$LIVE/tts"
    log "tts: restart $UNIT"
    systemctl --user restart "$UNIT"
    local waited=0
    until curl -sf -m 5 "$TTS_URL/health" | jq -e '.ok == true' >/dev/null 2>&1; do
        ((waited += 2))
        ((waited <= TTS_WAIT_SECS)) || die "tts: no healthy /health after ${TTS_WAIT_SECS}s"
        sleep 2
    done
    check_tts
}

deploy_phone() {
    local before after
    adb -s "$SERIAL" get-state >/dev/null 2>&1 || die "phone: $SERIAL unreachable"
    before="$(phone_version_code)"
    log "phone: release build + install -r (installed versionCode ${before:-none})"
    capped "$PHONE_DEPLOY" "$LIVE" --release || die "phone: phone_deploy.sh exit $?"
    after="$(phone_version_code)"
    if [[ -z $after ]] || ((after <= ${before:-0})); then
        die "phone: versionCode ${after:-none} did not move past ${before:-none}"
    fi
    check_phone
}

main() {
    if [[ ${1:-} == --health ]]; then
        check_desktop
        check_tts
        check_phone
        log "all healthy"
        return 0
    fi
    [[ -z ${1:-} ]] || die "unknown argument: $1"
    if [[ -z ${SUFLER_DEPLOY_PULLED:-} ]]; then
        update_checkout
        SUFLER_DEPLOY_PULLED=1 exec "$LIVE/scripts/deploy.sh" "$@"
    fi
    deploy_desktop
    deploy_tts
    deploy_phone
    log "all deployed"
}

main "$@"
