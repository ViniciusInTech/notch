#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/cache .build/config .build/security .build/clang-cache .build/module-cache
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
args=(--cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")
if [[ "${NOTCH_DISABLE_SANDBOX:-0}" == "1" ]]; then args+=(--disable-sandbox); fi
developer="$(xcode-select -p)"
if [[ "$developer" == */CommandLineTools ]]; then
    args+=(--build-system native)
    if [[ "${1:-}" == "test" ]]; then
        args+=(-Xswiftc -F -Xswiftc "$developer/Library/Developer/Frameworks"
               -Xswiftc -plugin-path -Xswiftc "$developer/usr/lib/swift/host/plugins/testing"
               -Xlinker -F -Xlinker "$developer/Library/Developer/Frameworks"
               -Xlinker -rpath -Xlinker "$developer/Library/Developer/Frameworks")
    fi
fi
exec swift "$@" "${args[@]}"
