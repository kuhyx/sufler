#!/bin/bash
# Builds sufler (Flutter web build + Dart AOT wrapper) and installs it as an
# Arch package via makepkg/pacman. Run from anywhere.
#
# The desktop app is the web build in a Chrome --app window served by a
# loopback wrapper (see the flutter-desktop-to-chrome skill): Flutter's Linux
# embedder manages ~20fps at 4K where Chrome sustains ~144fps.
#
# Requires: flutter (AUR flutter-bin; install it yourself, it needs a TTY),
# base-devel (installed here if missing), sudo for pacman.

set -euo pipefail

PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PACKAGING_DIR
REPO_DIR="$(dirname "$PACKAGING_DIR")"
readonly REPO_DIR
BUILD_DIR="$(mktemp -d)"
readonly BUILD_DIR

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

require_tools() {
    if ! command -v flutter >/dev/null; then
        echo "Error: flutter not found; install flutter-bin from the AUR." >&2
        exit 1
    fi
    if ! command -v makepkg >/dev/null; then
        sudo pacman -S --needed --noconfirm base-devel
    fi
}

# pubspec 1.2.3+4 -> 1.2.3, so the package version tracks the app's.
pubspec_version() {
    grep -m1 '^version:' "$REPO_DIR/pubspec.yaml" |
        sed -e 's/^version:[[:space:]]*//' -e 's/+.*//'
}

build() {
    echo "==> flutter build web --release --no-web-resources-cdn"
    # --no-web-resources-cdn: CanvasKit ships in the bundle, so the app
    # starts offline (the default loads it from www.gstatic.com).
    (cd "$REPO_DIR" && flutter build web --release --no-web-resources-cdn)
    echo "==> dart build cli (wrapper)"
    # `dart build cli`, not `dart compile exe`: sqlite3 has native build
    # hooks, which `dart compile` refuses. Emits bundle/bin + bundle/lib.
    rm -rf "$REPO_DIR/build/cli"
    (cd "$REPO_DIR" && dart build cli -t bin/sufler_desktop.dart -o build/cli)
}

# PKGBUILD's pkgver is static (makepkg wants it so); refuse to package a
# build whose pubspec version it does not match, rather than mislabel it.
check_version() {
    local want have
    want="$(pubspec_version)"
    have="$(grep -m1 '^pkgver=' "$PACKAGING_DIR/PKGBUILD" | cut -d= -f2)"
    if [[ "$want" != "$have" ]]; then
        echo "Error: PKGBUILD pkgver=$have but pubspec says $want; bump it." >&2
        exit 1
    fi
}

install_package() {
    echo "==> makepkg sufler $(pubspec_version)"
    # BUILDDIR/PKGDEST keep makepkg's src/ pkg/ and the tarball out of the repo.
    (cd "$PACKAGING_DIR" &&
        SUFLER_REPO="$REPO_DIR" BUILDDIR="$BUILD_DIR" PKGDEST="$BUILD_DIR" \
            makepkg -sif --noconfirm)
}

main() {
    require_tools
    check_version
    build
    install_package
    echo "==> Done. Run 'sufler' (or pick Sufler from the launcher)."
}

main "$@"
