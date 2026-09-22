@echo off
title SECRET EMKO Neural Graphics v2 - Full Neural Installer
echo ================================================================
echo  SECRET EMKO FULL NEURAL
echo  RTX 50 SERIES + SERVER/ENVIRONMENT PERMISSION REQUIRED
echo ================================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install-SecretEMKO.ps1" -Mode FullNeural
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" echo Installer exit code: %ERR%
pause
exit /b %ERR%
