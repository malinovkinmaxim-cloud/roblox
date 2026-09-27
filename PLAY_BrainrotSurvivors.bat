@echo off
rem ============================================================
rem  BRAINROT SURVIVORS - double-click to open the game in Roblox Studio.
rem  Nothing is downloaded or built: it opens the ready BrainrotSurvivors.rbxlx
rem  (the whole game is inside that one file). In Studio press Play (F5).
rem ============================================================
cd /d "%~dp0"
if not exist "BrainrotSurvivors.rbxlx" (
    echo ERROR: BrainrotSurvivors.rbxlx must be next to this file.
    pause
    exit /b 1
)
set "STUDIO="
for /d %%D in ("%LOCALAPPDATA%\Roblox\Versions\*") do (
    if exist "%%D\RobloxStudioBeta.exe" set "STUDIO=%%D\RobloxStudioBeta.exe"
)
if defined STUDIO (
    start "" "%STUDIO%" "%CD%\BrainrotSurvivors.rbxlx"
) else (
    start "" "BrainrotSurvivors.rbxlx"
)
echo Opening Roblox Studio... press Play (F5) when it is loaded.
timeout /t 4 >nul
