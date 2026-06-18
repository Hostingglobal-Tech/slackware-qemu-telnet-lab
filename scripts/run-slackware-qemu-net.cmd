@echo off
setlocal

set "SCRIPT=%~dp0run-slackware-qemu-net.ps1"

if not exist "%SCRIPT%" (
  echo Script not found: %SCRIPT%
  pause
  exit /b 1
)

echo Starting Slackware 2.0.0 on Windows-host QEMU...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 pause

