@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "DROP_DIR=%SCRIPT_DIR%NewSounds"
set "TOOL=%SCRIPT_DIR%..\Tools\add_sound.py"

where python >nul 2>nul
if errorlevel 1 (
    echo Python was not found on PATH. Install Python 3 from python.org, then run this again.
    pause
    exit /b 1
)

echo Looking for mp3 files in "%DROP_DIR%" ...
echo.
python "%TOOL%" --drop-folder "%DROP_DIR%"

echo.
pause
