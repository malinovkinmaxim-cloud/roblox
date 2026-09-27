#!/bin/bash
# ============================================================
#  BRAINROT SURVIVORS - full offline verification
#  needs on PATH: rojo, lune, luau-lsp (+ Roblox type definitions)
#    ROBLOX_TYPES=/path/to/globalTypes.d.luau  (from the luau-lsp repo, scripts/globalTypes.d.luau)
# ============================================================
set -e
cd "$(dirname "$0")/.."
TYPES="${ROBLOX_TYPES:-globalTypes.d.luau}"

echo "== sourcemap";      rojo sourcemap default.project.json -o sourcemap.json
if [ -f "$TYPES" ]; then
  echo "== type check";   luau-lsp analyze --definitions=@roblox="$TYPES" --sourcemap=sourcemap.json src
  echo "== properties";   python3 tools/check_props.py "$TYPES" src
else
  echo "(skipping type + property checks: set ROBLOX_TYPES)"
fi
echo "== unit tests";     lune run tests/run.luau
echo "== end-to-end";     lune run tests/e2e.luau
echo "== soak (2 full runs)"; lune run tests/soak.luau
echo "== balance (bot)";  lune run tests/sim.luau 3 Goober 0.8
if python3 -c "import PIL" 2>/dev/null; then
  echo "== UI (visual)";    tools/ui_check.sh | tail -1
else
  echo "(skipping the visual UI check: pip install pillow)"
fi
echo "== build";          rojo build default.project.json -o BrainrotSurvivors.rbxlx
cp BrainrotSurvivors.rbxlx ../BrainrotSurvivors.rbxlx
echo "ALL GOOD"
