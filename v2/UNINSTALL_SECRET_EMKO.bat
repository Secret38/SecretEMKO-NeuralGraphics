@echo off
title SECRET EMKO Neural Graphics v2 Uninstaller
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Uninstall-SecretEMKO.ps1"
set ERR=%ERRORLEVEL%
echo.
pause
exit /b %ERR%
