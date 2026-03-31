<#
.SYNOPSIS
    Runs PowerShell ScriptAnalyzer and fails on errors.
.DESCRIPTION
    Uses the repository-owned analyzer settings file and reports only error
    diagnostics as build failures.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $projectRoot '.config\PSScriptAnalyzerSettings.psd1'

function Get-TrackedPowerShellFiles {
    param([Parameter(Mandatory)][string]$Root)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        try {
            $tracked = & git -C $Root ls-files -- '*.ps1' '*.psm1' 2>$null
            if ($LASTEXITCODE -eq 0 -and $tracked) {
                return @(
                    $tracked |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                        ForEach-Object { Join-Path $Root $_ }
                )
            }
        }
        catch {
            # Fall back to filesystem enumeration below.
        }
    }

    return @(
        Get-ChildItem -Path $Root -Recurse -File -Include '*.ps1', '*.psm1' |
            ForEach-Object { $_.FullName }
    )
}

try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
}
catch {
    Write-Error "PSScriptAnalyzer is required for lint checks: $($_.Exception.Message)"
    exit 1
}

if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
    Write-Error 'Invoke-ScriptAnalyzer is not available. Install PSScriptAnalyzer to run lint checks.'
    exit 1
}

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Error "Analyzer settings file not found: $settingsPath"
    exit 1
}

$files = Get-TrackedPowerShellFiles -Root $projectRoot
if (-not $files -or $files.Count -eq 0) {
    Write-Host 'No PowerShell files were found to lint.'
    exit 0
}

$diagnostics = @()
foreach ($file in $files) {
    $diagnostics += Invoke-ScriptAnalyzer -Path $file -Settings $settingsPath
}
$errors = @($diagnostics | Where-Object { $_.Severity -eq 'Error' })

if ($errors.Count -gt 0) {
    Write-Host 'Lint errors found:' -ForegroundColor Red
    foreach ($item in $errors) {
        $location = if ($item.Line) { ":$($item.Line)" } else { '' }
        Write-Host "  $($item.ScriptName)$location [$($item.RuleName)] $($item.Message)" -ForegroundColor Red
    }
    exit 1
}

$warningCount = @($diagnostics | Where-Object { $_.Severity -eq 'Warning' }).Count
if ($warningCount -gt 0) {
    Write-Host "Lint passed with $warningCount warning(s)." -ForegroundColor Yellow
}
else {
    Write-Host "Lint passed for $($files.Count) file(s)." -ForegroundColor Green
}

exit 0
