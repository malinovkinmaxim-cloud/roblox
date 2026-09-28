#!/bin/bash
# ============================================================
#  67 SURVIVAL - double-click to open the game in Roblox Studio.
#  Nothing is downloaded or built: it opens the ready 67Survival.rbxlx
#  (the whole game is inside that one file). In Studio press Play (F5).
# ============================================================
cd "$(dirname "$0")" || exit 1
[ -f 67Survival.rbxlx ] || { echo "ERROR: 67Survival.rbxlx must be next to this file."; exit 1; }
if [ "$(uname -s)" = "Darwin" ]; then
    open -a "RobloxStudio" 67Survival.rbxlx 2>/dev/null || open 67Survival.rbxlx
else
    xdg-open 67Survival.rbxlx 2>/dev/null || echo "Open 67Survival.rbxlx in Roblox Studio."
fi
echo "Opening Roblox Studio... press Play (F5) when it is loaded."
