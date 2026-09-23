@echo off
setlocal
title Vencord Auto-Patcher - Setup
echo ==========================================
echo   Vencord Auto-Patcher - Setup
echo ==========================================
echo.
echo This will:
echo   1. Download the latest script to %LOCALAPPDATA%\VencordAutoPatcher
echo   2. Add it to your Windows startup
echo   3. Optionally run it now
echo.
echo Already installed? Running this again upgrades it in place.
echo.

set "SCRIPT=%LOCALAPPDATA%\VencordAutoPatcher\Vencord-AutoPatcher.ps1"
set "DOWNLOAD=%TEMP%\Vencord-AutoPatcher-setup.ps1"

echo [1/2] Downloading latest script...
rem Download to TEMP first so a failed download never touches an existing install
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/CyberKird/vencord-autopatcher/releases/latest/download/Vencord-AutoPatcher.ps1' -OutFile $env:DOWNLOAD"
if errorlevel 1 (
    echo ERROR: Could not download the script. Check your internet connection.
    pause
    exit /b 1
)
echo       Done.

echo [2/2] Installing...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DOWNLOAD%" -Install
set "RESULT=%ERRORLEVEL%"
del "%DOWNLOAD%" 2>nul
if not "%RESULT%"=="0" (
    echo ERROR: Install failed. Details are in %TEMP%\VencordAutoPatcher.log
    pause
    exit /b 1
)

echo.
echo ==========================================
echo   Setup complete!
echo.
echo   Vencord will now re-patch Discord every
echo   time you log into Windows. The patcher
echo   also keeps itself up to date.
echo.
echo   To uninstall: delete the shortcut from
echo   Win+R ^> shell:startup
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
