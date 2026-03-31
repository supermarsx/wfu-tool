@echo off
title wfu-tool Cleanup
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin for registry cleanup...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-TestFiles.ps1"
pause
