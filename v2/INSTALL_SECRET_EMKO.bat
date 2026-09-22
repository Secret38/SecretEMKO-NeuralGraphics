@echo off
title SECRET EMKO Neural Graphics v2 - RP Visual Installer
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install-SecretEMKO.ps1" -Mode RPVisual
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" echo Installer exit code: %ERR%
pause
exit /b %ERR%
