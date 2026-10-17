#!/bin/bash
# Copies build/Gaxo.app to ~/Applications/Gaxo.app (no password needed).
# Replaces an existing Gaxo.app only if this project installed it.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="build/Gaxo.app"
DEST_DIR="${GAXO_INSTALL_DIR:-$HOME/Applications}"
DEST="$DEST_DIR/Gaxo.app"
MARKER="Contents/Resources/gaxo-build-marker"

if [ ! -f "$SRC/$MARKER" ]; then
    echo "error: $SRC not found; run scripts/build-app.sh first" >&2
    exit 1
fi

if [ -e "$DEST" ]; then
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
    if [ ! -f "$DEST/$MARKER" ] || [ "$id" != "com.gaxo.Gaxo" ]; then
        echo "error: $DEST exists and was not installed by Gaxo's scripts; refusing to replace it" >&2
        exit 1
    fi
    if pgrep -f "$DEST/Contents/MacOS/Gaxo" >/dev/null; then
        echo "error: Gaxo is running from $DEST; quit it first" >&2
        exit 1
    fi
    rm -rf "$DEST"
fi

mkdir -p "$DEST_DIR"
ditto "$SRC" "$DEST"
codesign --verify --strict "$DEST"
echo "Installed $DEST"
