@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL_FIVEM.ps1"
if errorlevel 1 (
  echo.
  echo Installation reported an error. Read the message above.
  pause
  exit /b 1
)
echo.
echo Installation complete.
pause
