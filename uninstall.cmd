@echo off
setlocal
cd /d "%~dp0"

echo Quitando el arranque automatico de F1 Tray Monitor...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-autostart.ps1"
echo.
pause
