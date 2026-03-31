<#
.SYNOPSIS
    Dry-run of the upgrade engine with all destructive actions skipped.
    Runs pre-flight checks, version detection, and download URL resolution
    without actually modifying the system or downloading files.
    Useful for testing the full flow on a target machine.
#>
param(
    [string]$TargetVersion = '25H2'
)

$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  DRY RUN -- wfu-tool' -ForegroundColor Cyan
Write-Host '  ===================================' -ForegroundColor Cyan
Write-Host "  Target: $TargetVersion" -ForegroundColor White
Write-Host '  (No system changes will be made)' -ForegroundColor DarkGray
Write-Host ''

# Run the main script with -WhatIf and all skip flags
# This will log what WOULD happen without doing it
$logPath = Join-Path $env:TEMP "WFU_TOOL_DryRun_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$dlPath = Join-Path $env:TEMP 'WFU_TOOL_DryRunDL'

& (Join-Path $projectRoot 'wfu-tool.ps1') `
    -TargetVersion $TargetVersion `
    -NoReboot `
    -LogPath $logPath `
    -DownloadPath $dlPath `
    -SkipRepair `
    -SkipCumulativeUpdates `
    -DirectIso `
    -MaxRetries 1 `
    -WhatIf

Write-Host ''
Write-Host "  Log saved to: $logPath" -ForegroundColor DarkGray
Write-Host ''
