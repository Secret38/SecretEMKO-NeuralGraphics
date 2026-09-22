@echo off
title SECRET EMKO Neural Graphics v2 Installer
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install-SecretEMKO.ps1"
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" echo Installer exit code: %ERR%
pause
exit /b %ERR%
