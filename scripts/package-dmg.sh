#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
APP="$ROOT/dist/Notch.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE="$(mktemp -d "$ROOT/dist/.dmg-stage.XXXXXX")"
TEMP_DMG="$ROOT/dist/.Notch-${VERSION}-$$.dmg"
cleanup() { rm -rf "$STAGE"; rm -f "$TEMP_DMG"; }
trap cleanup EXIT
ditto "$APP" "$STAGE/Notch.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$STAGE/"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then SetFile -a C "$STAGE"; fi
hdiutil create -volname Notch -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$TEMP_DMG"
hdiutil verify "$TEMP_DMG"
mv -f "$TEMP_DMG" "$ROOT/dist/Notch-${VERSION}.dmg"
cp "$ROOT/dist/Notch-${VERSION}.dmg" "$ROOT/dist/Notch.dmg"
(cd "$ROOT/dist" && shasum -a 256 "Notch-${VERSION}.dmg" Notch.dmg > SHA256SUMS.txt)
mkdir -p "$ROOT/installers"
cp "$ROOT/dist/Notch.dmg" "$ROOT/installers/Notch.dmg"
(cd "$ROOT/installers" && shasum -a 256 Notch.dmg > SHA256SUMS.txt)
printf '\nInstalador criado: %s\n' "$ROOT/dist/Notch-${VERSION}.dmg"
