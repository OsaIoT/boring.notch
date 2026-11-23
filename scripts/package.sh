#!/usr/bin/env bash
#
# Builds the zip attached to GitHub releases.
#
#   ./scripts/package.sh        # -> build/release/Boring-Notch-Plus.zip
#
# Ad-hoc signed on purpose: a development certificate would put its
# owner's name in every downloaded copy, and the app isn't notarized either
# way, so people who download it follow the README's first-launch steps.
#
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="build/package"
OUT_DIR="build/release"
ZIP="${OUT_DIR}/Boring-Notch-Plus.zip"
LOG="${OUT_DIR}/package.log"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$DEVELOPER_DIR" != *.app/* ]]; then
        [[ -d /Applications/Xcode.app ]] || fail "Xcode is required."
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
export DEVELOPER_DIR

mkdir -p "$OUT_DIR"
say "Building an ad-hoc signed Release (log in $LOG)"
if ! xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
        -derivedDataPath "$BUILD_DIR" DEVELOPMENT_TEAM= "CODE_SIGN_IDENTITY=-" build >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -20 >&2 || true
    fail "The build failed. Full log: $LOG"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "${BUILD_DIR}/Build/Products/Release/Boring Notch.app" "$STAGE/Boring Notch+.app"
codesign --verify --deep --strict "$STAGE/Boring Notch+.app"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Boring Notch+.app" "$ZIP"
say "Created $ZIP ($(du -h "$ZIP" | cut -f1))"
