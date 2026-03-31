<#
.SYNOPSIS
    Verifies PowerShell formatting without modifying files.
.DESCRIPTION
    Formats every tracked .ps1 and .psm1 file in memory and fails if the
    formatter would change any content on disk.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

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
        } catch {
            # Fall back to filesystem enumeration below.
        }
    }

    return @(
        Get-ChildItem -Path $Root -Recurse -File -Include '*.ps1', '*.psm1' |
            ForEach-Object { $_.FullName }
    )
}

function Normalize-Newlines {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
} catch {
    Write-Error "PSScriptAnalyzer is required for formatting checks: $($_.Exception.Message)"
    exit 1
}

if (-not (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue)) {
    Write-Error 'Invoke-Formatter is not available. Install PSScriptAnalyzer to run formatting checks.'
    exit 1
}

$files = Get-TrackedPowerShellFiles -Root $projectRoot
if (-not $files -or $files.Count -eq 0) {
    Write-Host 'No PowerShell files were found to format.'
    exit 0
}

$violations = New-Object System.Collections.Generic.List[string]

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) {
        continue
    }

    $original = [System.IO.File]::ReadAllText($file)
    $formatted = Invoke-Formatter -ScriptDefinition (Normalize-Newlines $original)

    if ((Normalize-Newlines $original) -ne (Normalize-Newlines $formatted)) {
        $relative = $file.Replace($projectRoot, '').TrimStart('\')
        [void]$violations.Add($relative)
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Formatting violations found:' -ForegroundColor Red
    foreach ($item in $violations) {
        Write-Host "  $item" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Formatting check passed for $($files.Count) file(s)." -ForegroundColor Green
exit 0
