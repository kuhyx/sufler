#!/bin/bash

# ============================================================================
# Build sufler's release APK in stages that each fit the 60 s action cap.
# A one-shot `flutter build apk --release` holds a build slot ~73 s (JVM start
# + full gradle + Dart AOT); ci_apk_stage.sh splits it into prep, dart, kotlin
# and assemble on a warm gradle daemon, releasing the slot between stages.
#
# Usage: scripts/build_apk.sh [stage...]   (default: all four, in order)
# Env:   CI_APK_ABI (default android-arm64, the Pixel), see ci_apk_stage.sh.
# Prints the built APK path last (when assemble ran).
# Run one stage per call to keep each call under 60 s: build_apk.sh prep; ... dart; ...
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly STAGE_TOOL="$HOME/.claude/scripts/ci_apk_stage.sh"
readonly DEFAULT_STAGES=(prep dart kotlin assemble)

die() { printf '[build_apk] FAIL: %s\n' "$*" >&2; exit 1; }

# Exit 75: build queue full; a rerun keeps its place in the queue.
run_stage() {
    local rc
    while :; do
        rc=0
        "$STAGE_TOOL" "$REPO" "$1" || rc=$?
        ((rc == 75)) || return "$rc"
    done
}

main() {
    local stages=("$@") stage start apk
    ((${#stages[@]})) || stages=("${DEFAULT_STAGES[@]}")
    [[ -x $STAGE_TOOL ]] || die "missing $STAGE_TOOL"
    # Nothing compiles without the generated Firebase config.
    if [[ ! -f $REPO/lib/assist/firebase_local.dart ]]; then
        local extra=()
        [[ -d $HOME/.config/crdt-sync ]] || extra=(--placeholder)
        (cd "$REPO" && dart run tool/write_firebase_config.dart "${extra[@]}") \
            || die "write_firebase_config failed"
    fi
    for stage in "${stages[@]}"; do
        start=$SECONDS
        # With no source change gradle leaves the old APK untouched and
        # ci_apk_stage's "APK newer than prep" guard fails; drop it so
        # assemble repackages (or restores it from the build cache).
        if [[ $stage == assemble && -d $REPO/build/app/outputs ]]; then
            find "$REPO/build/app/outputs" -name '*.apk' -delete
        fi
        run_stage "$stage" || die "stage $stage exit $?"
        printf '[build_apk] %s %ds\n' "$stage" "$((SECONDS - start))"
    done
    # Single-stage calls (one tool call per stage) only print the APK at the end.
    [[ ${stages[-1]} == assemble ]] || return 0
    apk="$REPO/build/app/outputs/flutter-apk/app-release.apk"
    [[ -f $apk ]] || apk="$(find "$REPO/build/app/outputs" -name '*release*.apk' -print -quit)"
    [[ -n $apk && -f $apk ]] || die "no release apk under build/app/outputs"
    printf '%s\n' "$apk"
}

main "$@"
