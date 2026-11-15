@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0start-monitor.vbs" (
  echo No se encuentra start-monitor.vbs en esta carpeta.
  pause
  exit /b 1
)

rem Arranca el monitor sin ventana de consola.
start "" wscript.exe "%~dp0start-monitor.vbs"
exit /b 0
