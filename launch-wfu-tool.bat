@echo off
setlocal EnableDelayedExpansion

:: Store the script directory before anything else
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

title wfu-tool
color 0B

:: ================================================================
::  Auto-elevation: re-launch as Administrator if needed
:: ================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Requesting administrator privileges...
    echo.
    :: Write a temporary VBScript for elevation (works on all Windows 11 builds)
    set "VBS=%TEMP%\elevate_upgrade.vbs"
    echo Set UAC = CreateObject^("Shell.Application"^) > "!VBS!"
    echo UAC.ShellExecute "cmd.exe", "/k cd /d ""!SCRIPT_DIR!"" && ""!SCRIPT_DIR!\launch-wfu-tool.bat""", "", "runas", 1 >> "!VBS!"
    cscript //nologo "!VBS!"
    del /q "!VBS!" 2>nul
    exit /b
)

:: ================================================================
::  We are elevated -- set working directory and launch PowerShell
:: ================================================================
cd /d "%SCRIPT_DIR%"

echo.
echo   ================================================================
echo   wfu-tool -- Starting...
echo   ================================================================
echo   Working directory: %CD%
echo.

:: Use -Command instead of -File to completely bypass execution policy
:: Read the script content and execute it in-process
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "& { Set-ExecutionPolicy -Scope Process -Force Bypass 2>$null; . '%SCRIPT_DIR%\launch-wfu-tool.ps1' -ScriptRoot '%SCRIPT_DIR%' }"

echo.
if %errorlevel% neq 0 (
    color 0C
    echo   ================================================================
    echo   ERROR: Script exited with code %errorlevel%
    echo   ================================================================
) else (
    echo   ================================================================
    echo   Script finished.
    echo   ================================================================
)
echo.
echo   Press any key to close this window...
pause >nul
