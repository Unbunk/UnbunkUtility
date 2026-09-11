@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "DROP_DIR=%SCRIPT_DIR%NewSounds"
set "TOOL=%SCRIPT_DIR%..\Tools\add_sound.py"
set "EXTRA_ARGS=%*"

rem Find a Python that actually runs. The "python.exe" on PATH is often the
rem Microsoft Store app-execution-alias stub: `where python` finds it, but
rem launching it fails with "The system cannot find the file" when the Store
rem package isn't installed. So probe each candidate by running it.
set "PY="
call :try py -3
call :try python
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do call :try "%%D\python.exe"
for /d %%D in ("%ProgramFiles%\Python3*") do call :try "%%D\python.exe"

if not defined PY (
    echo No working Python 3 was found.
    echo Install it from python.org ^(tick "Add python.exe to PATH"^), then run this again.
    echo.
    pause
    exit /b 1
)

echo Using Python: %PY%
echo Looking for mp3 files in "%DROP_DIR%" ...
echo.
%PY% "%TOOL%" --drop-folder "%DROP_DIR%" %EXTRA_ARGS%

echo.
pause
exit /b 0

:try
if defined PY exit /b 0
%* -V >nul 2>nul
if errorlevel 1 exit /b 0
set "PY=%*"
exit /b 0
