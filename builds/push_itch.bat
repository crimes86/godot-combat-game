@echo off
REM ============================================================================
REM Ashbane - itch.io Push Script
REM ============================================================================
REM Usage: Run this from the builds folder after exporting from Godot
REM
REM Before first use:
REM   1. Install butler: https://broth.itch.zone/butler/windows-amd64/LATEST/archive/default
REM   2. Add butler to PATH or edit BUTLER_PATH below
REM   3. Run: butler login
REM   4. Update ITCH_USER and GAME_NAME below
REM ============================================================================

SET ITCH_USER=crimes86
SET GAME_NAME=ashbane
SET BUTLER_PATH=butler

REM Windows build
IF EXIST "windows" (
    echo Pushing Windows build...
    %BUTLER_PATH% push ./windows %ITCH_USER%/%GAME_NAME%:windows
) ELSE (
    echo No windows folder found. Export from Godot first.
)

REM Linux build (for dedicated server)
IF EXIST "linux" (
    echo Pushing Linux build...
    %BUTLER_PATH% push ./linux %ITCH_USER%/%GAME_NAME%:linux
)

echo.
echo Done! Check status with: butler status %ITCH_USER%/%GAME_NAME%
pause
