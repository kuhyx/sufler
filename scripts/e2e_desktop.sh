#!/bin/bash
# End-to-end check of the DESKTOP app (web build + loopback wrapper + Chrome)
# on an invisible Xvfb display with a muted browser: never a window on kuhy's
# screens, never sound on his speakers. Flows: DOCS-features.md.
#
#   scripts/e2e_desktop.sh build      # flutter build web + dart build cli
#   scripts/e2e_desktop.sh up         # Xvfb :79, wrapper :8792, scratch browser
#   scripts/e2e_desktop.sh wrapper    # restart only the wrapper (after a rebuild)
#   scripts/e2e_desktop.sh F1 .. F7   # one flow per call (each < 60 s)
#   scripts/e2e_desktop.sh down       # stop all three units
#
# Long-lived processes run as transient `systemd-run --user` units: anything
# started from a shell call dies with that call's scope. The browser gets a
# scratch --user-data-dir (never ~/.local/share/sufler/chrome-profile) and a
# CDP port. Artefacts (screenshots, downloads; they show copyrighted script
# text) go to private/e2e/, which is gitignored.
#
# Env: SUFLER_SCRIPT_PDF (default private/krasnale.pdf), E2E_ROLE (character
# id kuhy plays, default zagiewka; piaskowy-wilk also kept green),
# SUFLER_AUDIO_PACK (F6, F7; default: the PDF path with .sufler-audio.zip), SUFLER_BROWSER
# (default: first of chromium / google-chrome-stable), E2E_DISPLAY (:79).
# Needs: Xvfb (xorg-server-xvfb), python3 websocket-client, sqlite (python),
# ffmpeg (F6 clip durations, F7 WAV).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly E2E_DIR="${E2E_DIR:-$REPO_DIR/private/e2e}"
readonly DISPLAY_NUM="${E2E_DISPLAY:-:79}"
readonly CDP_PORT="${E2E_CDP_PORT:-9479}"
readonly APP_URL="http://127.0.0.1:8792"
readonly UNIT_PREFIX="sufler-e2e"
readonly UNITS=("$UNIT_PREFIX-browser" "$UNIT_PREFIX-wrapper" "$UNIT_PREFIX-xvfb")
readonly CAPPED="$HOME/.claude/scripts/capped.sh"

die() { echo "e2e: $*" >&2; exit 1; }

# Runs a build step capped when the shared cap script exists (kuhy's machine).
capped() {
    if [[ -x "$CAPPED" ]]; then CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"; else "$@"; fi
}

install_deps() {
    command -v Xvfb >/dev/null || sudo pacman -S --needed --noconfirm xorg-server-xvfb
    python3 -c 'import websocket' 2>/dev/null ||
        sudo pacman -S --needed --noconfirm python-websocket-client
}

find_browser() {
    local b
    for b in "${SUFLER_BROWSER:-}" /usr/bin/chromium /usr/bin/google-chrome-stable \
        /opt/google/chrome/chrome; do
        [[ -n "$b" && -x "$b" ]] && { echo "$b"; return; }
    done
    die "no Chrome-family browser found; set SUFLER_BROWSER"
}

build() {
    cd "$REPO_DIR"
    # Same flags as packaging/install_arch.sh: CanvasKit bundled, not CDN.
    capped flutter build web --release --no-web-resources-cdn
    rm -rf build/cli
    capped dart build cli -t bin/sufler_desktop.dart -o build/cli
}

wait_for() {  # wait_for <seconds> <command...>
    local tries=$(($1 * 5))
    shift
    while ((tries-- > 0)); do "$@" >/dev/null 2>&1 && return 0; sleep 0.2; done
    return 1
}

# (Re)starts only the wrapper, e.g. after `build`, keeping the browser data.
start_wrapper() {
    local exe="$REPO_DIR/build/cli/bundle/bin/sufler_desktop"
    [[ -x "$exe" && -f "$REPO_DIR/build/web/index.html" ]] || die "run '$0 build' first"
    systemctl --user stop "$UNIT_PREFIX-wrapper" 2>/dev/null || true
    systemd-run --user --collect --quiet --unit="$UNIT_PREFIX-wrapper" \
        "$exe" --web-root "$REPO_DIR/build/web" --no-browser
    wait_for 10 curl -sf "$APP_URL/api/health" || die "wrapper did not answer"
}

up() {
    install_deps
    ss -ltn | grep -q ':8792 ' && die "port 8792 busy (a real sufler running?); quit it first"
    local profile="$E2E_DIR/profile" browser
    browser="$(find_browser)"
    rm -rf "$profile"
    mkdir -p "$profile" "$E2E_DIR/downloads"

    systemd-run --user --collect --quiet --unit="$UNIT_PREFIX-xvfb" \
        Xvfb "$DISPLAY_NUM" -screen 0 1280x900x24 -nolisten tcp -noreset
    wait_for 10 test -S "/tmp/.X11-unix/X${DISPLAY_NUM#:}" || die "Xvfb did not start"

    start_wrapper

    # Same flags as lib/desktop/browser_launcher.dart browserArgs(), plus the
    # scratch profile, the CDP port, and no extensions (chromium-flags.conf
    # loads one that would fight this CDP session).
    systemd-run --user --collect --quiet --unit="$UNIT_PREFIX-browser" \
        --setenv=DISPLAY="$DISPLAY_NUM" \
        "$browser" "--app=$APP_URL" "--user-data-dir=$profile" --class=sufler \
        --no-first-run --password-store=basic --no-default-browser-check \
        --disable-extensions --mute-audio "--remote-debugging-port=$CDP_PORT" \
        --window-position=0,0 --window-size=1280,900
    wait_for 15 curl -sf "http://127.0.0.1:$CDP_PORT/json/version" || die "browser CDP not up"
    echo "e2e: up (display $DISPLAY_NUM, app $APP_URL, cdp $CDP_PORT, profile $profile)"
}

down() {
    local u
    for u in "${UNITS[@]}"; do
        systemctl --user stop "$u" 2>/dev/null || true
    done
    echo "e2e: down"
}

flow() {
    local pdf="${SUFLER_SCRIPT_PDF:-$REPO_DIR/private/krasnale.pdf}"
    python3 "$REPO_DIR/scripts/e2e/flows.py" "$1" --port "$CDP_PORT" \
        --out "$E2E_DIR" --pdf "$pdf" --display "$DISPLAY_NUM" --role "${E2E_ROLE:-zagiewka}" \
        --pack "${SUFLER_AUDIO_PACK:-${pdf%.*}.sufler-audio.zip}"
}

main() {
    case "${1:-}" in
        build) build ;;
        up) up ;;
        wrapper) start_wrapper ;;
        down) down ;;
        F[1-7]) flow "$1" ;;
        *) die "usage: $0 build|up|wrapper|F1..F7|down" ;;
    esac
}

main "$@"
