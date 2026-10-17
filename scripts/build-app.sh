#!/bin/bash
# Builds build/Gaxo.app (release), with its icon, and signs it.
# Writes only inside build/, and replaces build/Gaxo.app only if this script made it.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${GAXO_SIGN_ID:-Apple Development: (your identity)}"
APP="build/Gaxo.app"
MARKER="Contents/Resources/gaxo-build-marker"
ICONSET="build/.AppIcon.iconset"

swift build -c release --product Gaxo
BIN="$(swift build -c release --product Gaxo --show-bin-path)/Gaxo"

if [ -e "$APP" ]; then
    if [ -f "$APP/$MARKER" ]; then
        rm -rf "$APP"
    else
        echo "error: $APP exists but was not made by this script; refusing to replace it" >&2
        exit 1
    fi
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gaxo"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

rm -rf "$ICONSET"
"$BIN" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

touch "$APP/$MARKER"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --strict "$APP"

if otool -L "$APP/Contents/MacOS/Gaxo" | grep -q /opt/homebrew; then
    echo "error: Gaxo links against Homebrew at runtime" >&2
    exit 1
fi
echo "Built and signed $APP"
