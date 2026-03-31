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
    set "VBS=%TEMP%\wfu-tool-elevate.vbs"
    >"!VBS!" (
        echo Set UAC = CreateObject^("Shell.Application"^)
        echo scriptDir = WScript.Arguments(0)
        echo batPath = scriptDir ^& "\launch-wfu-tool.bat"
        echo argString = ""
        echo For i = 1 To WScript.Arguments.Count - 1
        echo     arg = WScript.Arguments(i)
        echo     If Len(argString) ^> 0 Then argString = argString ^& " "
        echo     arg = Replace(arg, """", """""")
        echo     argString = argString ^& """" ^& arg ^& """"
        echo Next
        echo command = "/k cd /d " ^& Chr(34) ^& scriptDir ^& Chr(34) ^& " && " ^& Chr(34) ^& batPath ^& Chr(34)
        echo If Len(argString) ^> 0 Then command = command ^& " " ^& argString
        echo UAC.ShellExecute "cmd.exe", command, "", "runas", 1
    )
    cscript //nologo "!VBS!" "%SCRIPT_DIR%" %*
    del /q "!VBS!" 2>nul
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
