#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/icon-cache" "$ROOT/.build/Notch.iconset"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/icon-cache"
swift -module-cache-path "$ROOT/.build/icon-cache" "$ROOT/scripts/GenerateIcon.swift" "$ROOT/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ROOT/.build/Notch.iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$ROOT/Resources/AppIcon.png" --out "$ROOT/.build/Notch.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$ROOT/scripts/pack-icon.py" "$ROOT/.build/Notch.iconset" "$ROOT/Resources/AppIcon.icns"
printf 'Ícone gerado: %s\n' "$ROOT/Resources/AppIcon.icns"
