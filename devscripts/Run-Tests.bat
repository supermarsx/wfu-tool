@echo off
:: Run the test suite -- auto-elevates if needed
title wfu-tool Test Suite
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin for HKLM registry tests...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Set-ExecutionPolicy -Scope Process Bypass -Force; . '.\tests\Test-Runner.ps1' }"
echo.
pause
