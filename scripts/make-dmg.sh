#!/bin/bash
# Builds an ad-hoc signed Gaxo.app and packages it as build/Gaxo-<version>.dmg
# for sharing. Ad-hoc signing keeps your developer certificate (and the email in
# its name) out of the shared app. Writes only inside build/.
set -euo pipefail
cd "$(dirname "$0")/.."

# A separate ad-hoc build, so the build/Gaxo.app that install.sh uses is untouched.
SHARE_APP="build/share/Gaxo.app"
GAXO_SIGN_ID=- GAXO_APP="$SHARE_APP" scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SHARE_APP/Contents/Info.plist")
DMG="build/Gaxo-$VERSION.dmg"
STAGE="build/.dmg-stage"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$SHARE_APP" "$STAGE/Gaxo.app"
cp LICENSE "$STAGE/LICENSE.txt"
cp README.md "$STAGE/README.md"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Gaxo $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
