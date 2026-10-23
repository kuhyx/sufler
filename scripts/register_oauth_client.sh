#!/bin/bash

# ============================================================================
# Walks the one step that cannot be automated -- registering the phone app's
# Android OAuth client -- and runs everything around it that can be.
# (Ported from tutor/scripts/register_oauth_client.sh.)
#
# Why a human has to click: an OAuth client is a credential and Google
# exposes no create API for one; the console is the only path. Until it
# exists, "Połącz z PC" in com.kuhy.sufler fails (Credential Manager says
# "canceled: account reauth failed" for UNREGISTERED_ON_API_CONSOLE).
#
# What this does for you:
#   * derives the SHA-1 from the real release keystore (android/key.properties),
#     refusing any key but the shared kuhy release key;
#   * opens the console and puts each field on the clipboard in form order;
#   * verifies on the phone by reading the screen back ("Połączono").
#
# Usage:
#   scripts/register_oauth_client.sh              # register, then verify
#   scripts/register_oauth_client.sh --sha1       # print the SHA-1 only
#   scripts/register_oauth_client.sh --verify-only
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly CONSOLE_URL="https://console.cloud.google.com/auth/clients?project=kuhy-syncs"
readonly PACKAGE="com.kuhy.sufler"
readonly CLIENT_NAME="sufler"
readonly DEVICE="${ADB_SERIAL:-23181JEGR08034}"
readonly CANONICAL_SHA256="9D:CC:2E:6C:05:3C:44:BB:05:07:90:3B:9D:D3:51:01:5E:A7:D4:31:5B:6E:E6:C8:53:DD:8D:80:7B:98:F8:46"

log() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
step() { printf '   %s\n' "$1"; }

# Copies to the clipboard when xclip exists; prints regardless (ssh-safe).
clip() {
    if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$1" | xclip -selection clipboard 2>/dev/null || true
        printf '   \033[32m[copied]\033[0m %s\n' "$1"
    else
        printf '   %s\n' "$1"
    fi
}

pause() { read -rp "   ...press Enter when that field is filled " _; }

prop() { grep -E "^$1=" "$2" | cut -d= -f2-; }

# Prints one fingerprint line (SHA1 or SHA256) of the release key.
fingerprint() {
    local properties="$REPO_DIR/android/key.properties"
    if [[ ! -f "$properties" ]]; then
        echo "error: $properties not found; cp ~/.android/release/key.properties there" >&2
        return 1
    fi
    local store password alias
    store="$(prop storeFile "$properties")"
    password="$(prop storePassword "$properties")"
    alias="$(prop keyAlias "$properties")"
    [[ "$store" = /* ]] || store="$REPO_DIR/android/app/$store"
    keytool -list -v -keystore "$store" -alias "$alias" \
        -storepass "$password" 2>/dev/null |
        grep -E "^[[:space:]]*$1:" | head -1 | sed "s/.*$1: //" | tr -d ' \r'
}

release_sha1() {
    local sha256
    sha256="$(fingerprint SHA256)"
    if [[ "$sha256" != "$CANONICAL_SHA256" ]]; then
        echo "error: keystore SHA-256 '$sha256' is not the shared kuhy key" >&2
        return 1
    fi
    fingerprint SHA1
}

verify_on_phone() {
    log "Verifying on the phone"
    if ! adb devices | grep -q "^$DEVICE"; then
        step "phone not attached; reconnect it and rerun with --verify-only"
        return 1
    fi
    step "Open a script, tab 'Ustawienia próby', scroll to 'Połącz z PC'."
    read -rp "   Enter when that tile is on screen: " _
    local dump
    dump="$(mktemp --suffix=.xml)"
    adb -s "$DEVICE" shell uiautomator dump /sdcard/sufler_ui.xml >/dev/null 2>&1
    adb -s "$DEVICE" pull /sdcard/sufler_ui.xml "$dump" >/dev/null 2>&1
    if grep -q 'Połączono' "$dump"; then
        rm -f "$dump"
        log "SIGNED IN: the phone can reach the PC through Firebase."
        return 0
    fi
    log "NOT SIGNED IN yet: tap 'Połącz' and pick the sync account."
    step "Screen dump: $dump. Then rerun: $0 --verify-only"
    return 1
}

register() {
    local sha1
    sha1="$(release_sha1)"
    [[ -n "$sha1" ]] || { echo "error: no SHA-1 from the keystore" >&2; exit 1; }

    log "Register ONE Android OAuth client in project kuhy-syncs"
    step "Google has no API for this. One form, three fields."
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$CONSOLE_URL" >/dev/null 2>&1 &
    else
        step "$CONSOLE_URL"
    fi
    sleep 2
    step "Click '+ CREATE CLIENT', set Application type = Android."
    step "Field 'Name':"
    clip "$CLIENT_NAME"
    pause
    step "Field 'Package name':"
    clip "$PACKAGE"
    pause
    step "Field 'SHA-1 certificate fingerprint':"
    clip "$sha1"
    pause
    step "Click CREATE. Do NOT touch the existing Web client (the token audience)."
    read -rp "   Propagation takes minutes. Install the APK, tap 'Połącz', then Enter: " _
    verify_on_phone
}

main() {
    case "${1:-}" in
        --verify-only) verify_on_phone ;;
        --sha1) release_sha1 ;;
        "") register ;;
        *)
            echo "usage: $0 [--verify-only|--sha1]" >&2
            exit 2
            ;;
    esac
}

main "$@"
