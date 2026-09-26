#!/bin/bash
# ============================================================
#  CHILE SIMULATOR - full offline verification
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
echo "== studio offline"; lune run tests/e2e_offline.luau
echo "== soak (5 min)";   lune run tests/soak.luau 5
echo "== build";          rojo build default.project.json -o ChileSimulator.rbxlx
echo "ALL GOOD"
