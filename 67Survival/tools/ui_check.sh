#!/bin/bash
# ============================================================
#  Visual UI check: exports every screen from the REAL scripts (offline engine: hub, menus,
#  a run with a boss, level up, pause, death, results, phone) and draws PNGs at
#  1920x1080, 1600x900, 1366x768, 1024x768 (tablet) and 844x390 (phone), reporting text
#  that shrinks too much, elements off screen and overlapping siblings.
#  needs: lune on PATH, python3 with Pillow
#  usage: tools/ui_check.sh [scene ...]      output: build/ui/png/
# ============================================================
set -e
cd "$(dirname "$0")/.."
lune run tools/export_gui.luau
python3 tools/render_gui.py build/ui build/ui/png "$@"
