#!/bin/bash
# Builds an ad-hoc signed Gaxo.app and packages it as build/Gaxo-<version>.dmg
# for sharing. Ad-hoc signing keeps your developer certificate (and the email in
# its name) out of the shared app. Writes only inside build/, and replaces
# build/Gaxo-<version>.dmg only if this script made it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
DMG="build/Gaxo-$VERSION.dmg"
# The checksum of the DMG this script made: a DMG that does not match it is not ours.
DMG_SUM="build/.Gaxo-$VERSION.dmg.sha256"
STAGE="build/.dmg-stage-$$"

sum() { shasum -a 256 "$1" | cut -d' ' -f1; }
refuse_foreign_dmg() {
    if [ -e "$DMG" ] && { [ ! -f "$DMG_SUM" ] || [ "$(sum "$DMG")" != "$(cat "$DMG_SUM")" ]; }; then
        echo "error: $DMG exists but was not made by this script; refusing to replace it" >&2
        exit 1
    fi
}
refuse_foreign_dmg

# A separate ad-hoc build, so the build/Gaxo.app that install.sh uses is untouched.
SHARE_APP="build/share/Gaxo.app"
GAXO_SIGN_ID=- GAXO_APP="$SHARE_APP" scripts/build-app.sh

mkdir "$STAGE" # fails if it exists: only a folder this run made is removed below
trap 'rm -rf "$STAGE"' EXIT
ditto "$SHARE_APP" "$STAGE/Gaxo.app"
cp LICENSE "$STAGE/LICENSE.txt"
cp README.md "$STAGE/README.md"
ln -s /Applications "$STAGE/Applications"

refuse_foreign_dmg # again: the build took a while
rm -f "$DMG" "$DMG_SUM"
hdiutil create -volname "Gaxo $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
sum "$DMG" > "$DMG_SUM"
echo "Built $DMG"
