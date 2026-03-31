@echo off
title wfu-tool CI Pipeline
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CI.ps1" %*
echo.
if %errorlevel% neq 0 (
    echo CI FAILED with exit code %errorlevel%
) else (
    echo CI PASSED
)
echo.
pause
