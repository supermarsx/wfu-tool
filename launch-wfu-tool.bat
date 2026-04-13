@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

title wfu-tool
color 0B

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Requesting administrator privileges...
    echo.
    set "WFU_ELEVATE_SCRIPT_DIR=%SCRIPT_DIR%"
    set "WFU_ELEVATE_ARGS=%*"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $scriptDir = $env:WFU_ELEVATE_SCRIPT_DIR; $batPath = Join-Path $scriptDir 'launch-wfu-tool.bat'; $argText = $env:WFU_ELEVATE_ARGS; if ([string]::IsNullOrWhiteSpace($argText)) { Start-Process -FilePath $batPath -WorkingDirectory $scriptDir -Verb RunAs | Out-Null } else { Start-Process -FilePath $batPath -WorkingDirectory $scriptDir -ArgumentList $argText -Verb RunAs | Out-Null }"
    set "ELEVATE_EXIT=!errorlevel!"
    set "WFU_ELEVATE_SCRIPT_DIR="
    set "WFU_ELEVATE_ARGS="
    if not "!ELEVATE_EXIT!"=="0" (
        color 0E
        echo.
        echo   Elevation was cancelled or failed.
        echo   Accept the UAC prompt or run this launcher from an elevated terminal.
        echo.
        echo   Press any key to close this window...
        pause ^>nul
    )
    exit /b
)

cd /d "%SCRIPT_DIR%"

echo.
echo   ================================================================
echo   wfu-tool -- Starting...
echo   ================================================================
echo   Working directory: %CD%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\launch-wfu-tool.ps1" -ScriptRoot "%SCRIPT_DIR%" %*

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
