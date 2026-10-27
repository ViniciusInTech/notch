#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
if [[ -n "$NOTARY_PROFILE" && "$IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE exige CODE_SIGN_IDENTITY com um certificado Developer ID Application." >&2
    exit 1
fi
"$ROOT/scripts/build.sh"
APP="$ROOT/dist/Notch.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE="$(mktemp -d "$ROOT/dist/.dmg-stage.XXXXXX")"
WORK="$(mktemp -d "$ROOT/dist/.dmg-work.XXXXXX")"
TEMP_DMG="$ROOT/dist/.Notch-${VERSION}-$$.dmg"
MOUNT=""
cleanup() {
    if [[ -n "$MOUNT" ]]; then hdiutil detach "$MOUNT" -quiet -force || true; fi
    rm -rf "$STAGE" "$WORK"; rm -f "$TEMP_DMG"
}
trap cleanup EXIT

# Window background with the drag instruction; Retina and standard sizes in one TIFF.
mkdir -p "$ROOT/.build/dmg-cache"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/dmg-cache" swift -module-cache-path "$ROOT/.build/dmg-cache" \
    "$ROOT/scripts/GenerateDMGBackground.swift" "$WORK/background.png" "$WORK/background@2x.png"
mkdir "$STAGE/.background"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGE/.background/background.tiff"

# License and notices already ship inside the app bundle; the window shows only what to drag.
ditto "$APP" "$STAGE/Notch.app"
ln -s /Applications "$STAGE/Aplicativos"

hdiutil create -volname Notch -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
[[ -d "$MOUNT" ]] || { echo "Não foi possível montar a imagem temporária." >&2; exit 1; }

# Finder stores icon positions and the background in the volume's .DS_Store.
# The disk name is passed as an argument, never interpolated into the script.
if ! osascript - "$(basename "$MOUNT")" <<'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 120, 860, 548}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 112
            set text size of viewOptions to 13
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "Notch.app" of container window to {170, 215}
            set position of item "Aplicativos" of container window to {490, 215}
            close
            open
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
APPLESCRIPT
then
    echo "Aviso: o Finder não aplicou o layout da janela. Autorize o Terminal a controlar o Finder em Automação e gere novamente." >&2
fi
# Added after the Finder pass, which drops a volume icon present before it.
cp "$ROOT/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then SetFile -a C "$MOUNT"; fi
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$TEMP_DMG"

if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp "$TEMP_DMG"
    codesign --verify --strict "$TEMP_DMG"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
    # Apple scans the image and the app inside it; stapling lets Gatekeeper verify offline.
    xcrun notarytool submit "$TEMP_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$TEMP_DMG"
    xcrun stapler validate "$TEMP_DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$TEMP_DMG"
else
    echo "Aviso: instalador não notarizado. O macOS mostrará o alerta de app não verificado. Veja docs/RELEASE.md." >&2
fi
hdiutil verify "$TEMP_DMG"

mv -f "$TEMP_DMG" "$ROOT/dist/Notch-${VERSION}.dmg"
cp "$ROOT/dist/Notch-${VERSION}.dmg" "$ROOT/dist/Notch.dmg"
(cd "$ROOT/dist" && shasum -a 256 "Notch-${VERSION}.dmg" Notch.dmg > SHA256SUMS.txt)
mkdir -p "$ROOT/installers"
cp "$ROOT/dist/Notch.dmg" "$ROOT/installers/Notch.dmg"
(cd "$ROOT/installers" && shasum -a 256 Notch.dmg > SHA256SUMS.txt)
printf '\nInstalador criado: %s\n' "$ROOT/dist/Notch-${VERSION}.dmg"
