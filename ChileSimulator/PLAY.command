#!/bin/bash
# ============================================================
#  CHILE SIMULATOR - one-click launch (macOS / Linux)
#  1) gets Rojo (downloads it once into tools/ if needed)
#  2) builds ChileSimulator.rbxlx from src/
#  3) opens it in Roblox Studio  -> just press Play
# ============================================================
cd "$(dirname "$0")" || exit 1
VERSION=7.4.4

ROJO="$(command -v rojo)"
[ -z "$ROJO" ] && [ -x tools/rojo ] && ROJO="tools/rojo"
if [ -z "$ROJO" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) ASSET=macos-aarch64 ;;
        Darwin-*) ASSET=macos-x86_64 ;;
        *) ASSET=linux-x86_64 ;;
    esac
    echo "[1/3] Downloading Rojo (only the first time)..."
    mkdir -p tools
    if curl -fsSL -o tools/rojo.zip "https://github.com/rojo-rbx/rojo/releases/download/v$VERSION/rojo-$VERSION-$ASSET.zip" \
        && unzip -o -q tools/rojo.zip -d tools; then
        rm -f tools/rojo.zip
        chmod +x tools/rojo
        ROJO="tools/rojo"
    fi
fi

if [ -n "$ROJO" ]; then
    echo "[2/3] Building the game..."
    "$ROJO" build default.project.json -o ChileSimulator.rbxlx || echo "Build failed - opening the last built version instead."
else
    echo "[2/3] Rojo not available - opening the prebuilt version."
fi

[ -f ChileSimulator.rbxlx ] || { echo "ERROR: ChileSimulator.rbxlx not found."; exit 1; }

echo "[3/3] Opening Roblox Studio..."
if [ "$(uname -s)" = "Darwin" ]; then
    open -a "RobloxStudio" ChileSimulator.rbxlx 2>/dev/null || open ChileSimulator.rbxlx
else
    xdg-open ChileSimulator.rbxlx 2>/dev/null || echo "Open ChileSimulator.rbxlx in Roblox Studio."
fi
echo "Done. In Studio press Play (F5)."
