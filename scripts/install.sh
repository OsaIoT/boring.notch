#!/usr/bin/env bash
#
# Builds Boring Notch+ from source and installs it in /Applications.
#
#   ./scripts/install.sh
#
# Signs with your "Apple Development" certificate when you have one, so
# macOS keeps the camera, microphone and screen recording permissions
# across updates. Without one it falls back to ad-hoc signing: the app
# works, but macOS asks for those permissions again after every rebuild.
# To pick a specific team: TEAM_ID=XXXXXXXXXX ./scripts/install.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Boring Notch+"
BUNDLE_ID="com.osaiot.boringnotch"
DESTINATION="/Applications/${APP_NAME}.app"
BUILD_DIR="build"
LOG="${BUILD_DIR}/install.log"
PRODUCT="${BUILD_DIR}/Build/Products/Release/Boring Notch.app"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }
is_running() { [[ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" == "true" ]]; }

# Xcode itself is needed, not just the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$DEVELOPER_DIR" != *.app/* ]]; then
        [[ -d /Applications/Xcode.app ]] || fail "Xcode is required. Install it from the App Store and open it once."
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi
export DEVELOPER_DIR

TEAM_ID="${TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | awk -F'= ' '/organizationalUnitName/ { print $2; exit }' || true)}"
if [[ -n "$TEAM_ID" ]]; then
    say "Signing with your Apple Development certificate (team $TEAM_ID)"
    SIGNING=(DEVELOPMENT_TEAM="$TEAM_ID" "CODE_SIGN_IDENTITY=Apple Development")
else
    say "No Apple Development certificate found: using ad-hoc signing"
    echo "    macOS will ask for camera, microphone and screen access again after each rebuild."
    echo "    The README explains how to get a free certificate."
    SIGNING=(DEVELOPMENT_TEAM= "CODE_SIGN_IDENTITY=-")
fi

mkdir -p "$BUILD_DIR"
say "Building (a few minutes the first time; log in $LOG)"
if ! xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
        -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates "${SIGNING[@]}" build >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -20 >&2 || true
    fail "The build failed. Full log: $LOG"
fi

if is_running; then
    # Quitting mid-recording would still save the video, but cut it short.
    if find "$HOME/Movies/Boring Notch" -name '*.mov' -mmin -1 2>/dev/null | grep -q .; then
        fail "A recording seems to be in progress. Stop it, then run this again."
    fi
    say "Quitting the running app"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        is_running || break
        sleep 0.5
    done
    is_running && fail "Boring Notch+ didn't quit. Quit it from the menu bar and run this again."
fi

say "Installing to $DESTINATION"
rm -rf "$DESTINATION"
ditto "$PRODUCT" "$DESTINATION"
open "$DESTINATION"
say "Done: Boring Notch+ is running."
