@echo off
rem ============================================================
rem  CHILE SIMULATOR - one-click launch (Windows)
rem  1) gets Rojo (downloads it once into tools\ if needed)
rem  2) builds ChileSimulator.rbxlx from src\
rem  3) opens it in Roblox Studio  -> just press Play
rem ============================================================
cd /d "%~dp0"
set "ROJO="
set "ROJO_URL=https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-windows-x86_64.zip"

where rojo >nul 2>nul && set "ROJO=rojo"
if not defined ROJO if exist "tools\rojo.exe" set "ROJO=tools\rojo.exe"
if not defined ROJO (
    echo [1/3] Downloading Rojo ^(only the first time^)...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { New-Item -ItemType Directory -Force 'tools' | Out-Null; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest '%ROJO_URL%' -OutFile 'tools\rojo.zip' -UseBasicParsing; Expand-Archive -Force 'tools\rojo.zip' 'tools'; Remove-Item 'tools\rojo.zip' } catch { exit 1 }"
    if exist "tools\rojo.exe" set "ROJO=tools\rojo.exe"
)

if defined ROJO (
    echo [2/3] Building the game...
    "%ROJO%" build default.project.json -o ChileSimulator.rbxlx
    if errorlevel 1 echo Build failed - opening the last built version instead.
) else (
    echo [2/3] Rojo not available - opening the prebuilt version.
)

if not exist "ChileSimulator.rbxlx" (
    echo ERROR: ChileSimulator.rbxlx not found.
    pause
    exit /b 1
)

echo [3/3] Opening Roblox Studio...
set "STUDIO="
for /d %%D in ("%LOCALAPPDATA%\Roblox\Versions\*") do (
    if exist "%%D\RobloxStudioBeta.exe" set "STUDIO=%%D\RobloxStudioBeta.exe"
)
if defined STUDIO (
    start "" "%STUDIO%" "%CD%\ChileSimulator.rbxlx"
) else (
    start "" "ChileSimulator.rbxlx"
)
echo Done. In Studio press Play (F5).
timeout /t 5 >nul
