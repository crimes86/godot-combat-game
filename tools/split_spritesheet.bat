@echo off
REM LPC Spritesheet Splitter - Windows Batch File
REM Usage: split_spritesheet.bat <input.png> <output_dir> [weapon|armor|shield|cape]

if "%~1"=="" (
    echo Usage: split_spritesheet.bat ^<input.png^> ^<output_dir^> [item_type]
    echo.
    echo Item types: weapon, armor, shield, cape, all
    echo.
    echo Example:
    echo   split_spritesheet.bat downloaded_sword.png assets\equipment\forged\weapons\stygian_blade weapon
    exit /b 1
)

set INPUT=%~1
set OUTPUT=%~2
set TYPE=%~3

if "%TYPE%"=="" set TYPE=weapon

python "%~dp0lpc_spritesheet_splitter.py" split "%INPUT%" "%OUTPUT%" --type %TYPE%
