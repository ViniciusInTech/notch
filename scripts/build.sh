#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -f "$ROOT/Resources/AppIcon.icns" || "$ROOT/scripts/GenerateIcon.swift" -nt "$ROOT/Resources/AppIcon.icns" ]]; then
    "$ROOT/scripts/generate-icon.sh"
fi
"$ROOT/scripts/swift.sh" build -c release
BIN_DIR="$("$ROOT/scripts/swift.sh" build -c release --show-bin-path)"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/dist/.notch-build.XXXXXX")"
TARGET="$ROOT/dist/Notch.app"
cleanup() {
    if [[ -d "$STAGE/Previous.app" && ! -e "$TARGET" ]]; then mv "$STAGE/Previous.app" "$TARGET"; fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
APP="$STAGE/Notch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Notch" "$APP/Contents/MacOS/Notch"
cp "$BIN_DIR/notch-hook" "$APP/Contents/MacOS/notch-hook"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime --entitlements "$ROOT/Resources/Notch.entitlements")
# Notarization requires a secure timestamp; ad hoc signatures cannot carry one.
if [[ "$IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/MacOS/notch-hook"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"
if [[ -e "$TARGET" ]]; then mv "$TARGET" "$STAGE/Previous.app"; fi
mv "$APP" "$TARGET"
printf '\nApp criado em %s\n' "$TARGET"
