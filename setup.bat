@echo off
title Vencord Auto-Patcher - Setup
echo ==========================================
echo   Vencord Auto-Patcher - One-Time Setup
echo ==========================================
echo.
echo This will:
echo   1. Download the latest script to C:\Scripts
echo   2. Add it to your Windows startup
echo   3. Optionally run it now
echo.

mkdir C:\Scripts 2>nul

echo [1/2] Downloading latest script...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/CyberKird/vencord-autopatcher/releases/latest/download/Vencord-AutoPatcher.ps1' -OutFile 'C:\Scripts\Vencord-AutoPatcher.ps1'"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Could not download the script. Check your internet connection.
    pause
    exit /b 1
)
echo       Done.

echo [2/2] Adding to startup...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Startup') + '\Vencord-AutoPatcher.lnk'); $sc.TargetPath = 'powershell.exe'; $sc.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\Scripts\Vencord-AutoPatcher.ps1\"'; $sc.Save()"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Could not create startup shortcut. Try running as Administrator.
    pause
    exit /b 1
)
echo       Done.

echo.
echo ==========================================
echo   Setup complete!
echo.
echo   Vencord will now re-patch Discord every
echo   time you log into Windows.
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
    exit
)
echo.
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Vencord-AutoPatcher.ps1"
pause
