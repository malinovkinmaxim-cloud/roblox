@echo off
rem ============================================================
rem  67 SURVIVAL - double-click to open the game in Roblox Studio.
rem  Nothing is downloaded or built: it opens the ready 67Survival.rbxlx
rem  (the whole game is inside that one file). In Studio press Play (F5).
rem ============================================================
cd /d "%~dp0"
if not exist "67Survival.rbxlx" (
    echo ERROR: 67Survival.rbxlx must be next to this file.
    pause
    exit /b 1
)
set "STUDIO="
for /d %%D in ("%LOCALAPPDATA%\Roblox\Versions\*") do (
    if exist "%%D\RobloxStudioBeta.exe" set "STUDIO=%%D\RobloxStudioBeta.exe"
)
if defined STUDIO (
    start "" "%STUDIO%" "%CD%\67Survival.rbxlx"
) else (
    start "" "67Survival.rbxlx"
)
echo Opening Roblox Studio... press Play (F5) when it is loaded.
timeout /t 4 >nul
