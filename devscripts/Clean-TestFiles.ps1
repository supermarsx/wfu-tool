<#
.SYNOPSIS
    Cleans up all test artifacts, temp files, and build outputs.
    Safe to run at any time -- only deletes generated files, never source.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  CLEANUP' -ForegroundColor Cyan
Write-Host '  =======' -ForegroundColor Cyan
Write-Host ''

$cleaned = 0

# Test temp files
$tempPatterns = @(
    "$env:TEMP\WFU_TOOL_*",
    "$env:TEMP\WFU_TOOL_*",
    "$env:TEMP\ms_cookies.txt"
)
foreach ($p in $tempPatterns) {
    $items = Get-Item $p -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($item.FullName)" -ForegroundColor DarkGray
        $cleaned++
    }
}

# Project temp/output files
$projectPatterns = @(
    '*.log',
    'wu-request.xml',
    'wu-response.xml',
    'test-*.txt'
)
foreach ($p in $projectPatterns) {
    $items = Get-ChildItem $projectRoot -Filter $p -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $($item.Name)" -ForegroundColor DarkGray
        $cleaned++
    }
}

# Download directory
$dlDir = 'C:\wfu-tool'
if (Test-Path $dlDir) {
    $dlSize = [math]::Round((Get-ChildItem $dlDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
    Write-Host "  Download dir: $dlDir ($dlSize MB)" -ForegroundColor Yellow
    Write-Host '  Delete download directory? [y/N]: ' -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host
    if ($confirm -match '^[yY]') {
        Remove-Item $dlDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $dlDir" -ForegroundColor DarkGray
        $cleaned++
    }
}

# IFEO hooks (safety cleanup)
$hookScript = "$env:SystemDrive\Scripts\get11.cmd"
if (Test-Path $hookScript) {
    Remove-Item $hookScript -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: $hookScript" -ForegroundColor DarkGray
    $cleaned++
}
$ifeoKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SetupHost.exe'
if (Test-Path $ifeoKey) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Remove-Item $ifeoKey -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: IFEO SetupHost.exe hook" -ForegroundColor DarkGray
        $cleaned++
    } else {
        Write-Host "  IFEO hook exists but needs admin to remove" -ForegroundColor Yellow
    }
}

# Resume scheduled task
try {
    $task = Get-ScheduledTask -TaskName 'wfu-tool-resume' -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName 'wfu-tool-resume' -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host '  Removed: wfu-tool-resume scheduled task' -ForegroundColor DarkGray
        $cleaned++
    }
} catch { }

# Resume registry key
$resumeKey = 'HKLM:\SOFTWARE\wfu-tool'
if (Test-Path $resumeKey) {
    Remove-Item $resumeKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Removed: Resume registry key" -ForegroundColor DarkGray
    $cleaned++
}

Write-Host ''
Write-Host "  Cleaned $cleaned item(s)." -ForegroundColor Green
Write-Host ''
