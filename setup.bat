@echo off
setlocal
title Vencord Auto-Patcher - Setup
echo ==========================================
echo   Vencord Auto-Patcher - Setup
echo ==========================================
echo.

set "SCRIPT=%LOCALAPPDATA%\VencordAutoPatcher\Vencord-AutoPatcher.ps1"
set "DOWNLOAD=%TEMP%\Vencord-AutoPatcher-setup.ps1"
set "ACTION=-Install"

set "EXISTING="
if exist "%SCRIPT%" set "EXISTING=1"
if exist "C:\Scripts\Vencord-AutoPatcher.ps1" set "EXISTING=1"

if not defined EXISTING goto :fresh
echo The patcher is already installed on this PC.
echo.
choice /c UR /n /m "[U]pdate it to the latest version, or [R]emove it? "
if errorlevel 2 set "ACTION=-Uninstall"
echo.
goto :download

:fresh
echo This will:
echo   1. Download the latest script to %LOCALAPPDATA%\VencordAutoPatcher
echo   2. Run it at every login, before Discord opens
echo   3. Optionally run it now
echo.

:download
echo Downloading the latest patcher...
rem Download to TEMP first so a failed download never touches an existing install
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/CyberKird/vencord-autopatcher/releases/latest/download/Vencord-AutoPatcher.ps1' -OutFile $env:DOWNLOAD"
if errorlevel 1 (
    echo ERROR: Could not download the script. Check your internet connection.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%DOWNLOAD%" %ACTION%
set "RESULT=%ERRORLEVEL%"
del "%DOWNLOAD%" 2>nul
if not "%RESULT%"=="0" (
    echo ERROR: Setup failed. Details are in %TEMP%\VencordAutoPatcher.log
    pause
    exit /b 1
)

if "%ACTION%"=="-Uninstall" (
    echo.
    pause
    exit /b 0
)

echo.
echo ==========================================
echo   Setup complete!
echo.
echo   Discord gets re-patched automatically
echo   after every Discord update, and the
echo   patcher keeps itself up to date.
echo.
echo   To remove it, run this file again.
echo ==========================================
echo.
choice /c YN /n /m "Run it now? [Y/N] "
if errorlevel 2 (
    echo.
    echo You're all set. Restart or log out to test.
    timeout /t 5 >nul
    exit /b 0
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
pause
