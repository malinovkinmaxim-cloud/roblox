#!/bin/bash
# ============================================================
#  BRAINROT SURVIVORS - double-click to open the game in Roblox Studio.
#  Nothing is downloaded or built: it opens the ready BrainrotSurvivors.rbxlx
#  (the whole game is inside that one file). In Studio press Play (F5).
# ============================================================
cd "$(dirname "$0")" || exit 1
[ -f BrainrotSurvivors.rbxlx ] || { echo "ERROR: BrainrotSurvivors.rbxlx must be next to this file."; exit 1; }
if [ "$(uname -s)" = "Darwin" ]; then
    open -a "RobloxStudio" BrainrotSurvivors.rbxlx 2>/dev/null || open BrainrotSurvivors.rbxlx
else
    xdg-open BrainrotSurvivors.rbxlx 2>/dev/null || echo "Open BrainrotSurvivors.rbxlx in Roblox Studio."
fi
echo "Opening Roblox Studio... press Play (F5) when it is loaded."
