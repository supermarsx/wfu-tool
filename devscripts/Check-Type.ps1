<#
.SYNOPSIS
    Performs PowerShell parse and safe-bootstrap validation.
.DESCRIPTION
    Parses all tracked PowerShell files and then safely loads the main
    entrypoints in isolated pwsh processes with test-mode guards enabled.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'wfu-tool-type'

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

function Test-ParsedFile {
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $lines = $errors | ForEach-Object {
            "  $($_.Extent.StartLineNumber): $($_.Message)"
        }
        throw [System.Management.Automation.RuntimeException]::new(
            "Parse errors in $Path`n$([string]::Join([Environment]::NewLine, $lines))"
        )
    }
}

function Escape-PowerShellSingleQuote {
    param([Parameter(Mandatory)][string]$Text)

    return $Text.Replace("'", "''")
}

function Invoke-SafeBootstrap {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $shellCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($shellCommand) {
        $pwsh = $shellCommand.Source
    } else {
        $pwsh = (Get-Command powershell -ErrorAction Stop).Source
    }
    $oldTestMode = $env:WFU_TOOL_TEST_MODE
    $env:WFU_TOOL_TEST_MODE = '1'
    $output = & $pwsh -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $env:WFU_TOOL_TEST_MODE = $oldTestMode

    if ($exitCode -ne 0) {
        $message = @(
            "Bootstrap failed for $Label."
            "Exit code: $exitCode"
            "Output:"
            ($output | ForEach-Object { "  $_" })
        ) -join [Environment]::NewLine
        throw [System.Management.Automation.RuntimeException]::new($message)
    }
}

if (-not (Test-Path -LiteralPath $tempRoot)) {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
}

$trackedFiles = Get-TrackedPowerShellFiles -Root $projectRoot
if (-not $trackedFiles -or $trackedFiles.Count -eq 0) {
    Write-Host 'No PowerShell files were found to type-check.'
    exit 0
}

foreach ($file in $trackedFiles) {
    if (Test-Path -LiteralPath $file) {
        Test-ParsedFile -Path $file
    }
}

$bootstrapChecks = @(
    @{
        Label = 'wfu-tool.ps1'
        Script = (Join-Path $projectRoot 'wfu-tool.ps1')
        Arguments = @(
            '-Mode', 'Headless',
            '-TargetVersion', '25H2',
            '-LogPath', (Join-Path $tempRoot 'wfu-tool-type.log'),
            '-DownloadPath', (Join-Path $tempRoot 'download'),
            '-NoReboot',
            '-SkipBypasses',
            '-SkipBlockerRemoval',
            '-SkipTelemetry',
            '-SkipRepair',
            '-SkipCumulativeUpdates',
            '-SkipNetworkCheck',
            '-SkipDiskCheck',
            '-SkipDirectEsd',
            '-SkipEsd',
            '-SkipFido',
            '-SkipMct',
            '-SkipAssistant',
            '-SkipWindowsUpdate'
        )
    }
    @{
        Label = 'launch-wfu-tool.ps1'
        Script = (Join-Path $projectRoot 'launch-wfu-tool.ps1')
        Arguments = @(
            '-Mode', 'Headless',
            '-TargetVersion', '25H2',
            '-LogPath', (Join-Path $tempRoot 'launch-type.log'),
            '-DownloadPath', (Join-Path $tempRoot 'download'),
            '-NoReboot',
            '-SkipBypasses',
            '-SkipBlockerRemoval',
            '-SkipTelemetry',
            '-SkipRepair',
            '-SkipCumulativeUpdates',
            '-SkipNetworkCheck',
            '-SkipDiskCheck',
            '-SkipDirectEsd',
            '-SkipEsd',
            '-SkipFido',
            '-SkipMct',
            '-SkipAssistant',
            '-SkipWindowsUpdate'
        )
    }
    @{
        Label = 'resume-wfu-tool.ps1'
        Script = (Join-Path $projectRoot 'resume-wfu-tool.ps1')
        Arguments = @(
            '-ScriptRoot', $projectRoot,
            '-TargetVersion', '25H2',
            '-LogPath', (Join-Path $tempRoot 'resume-type.log'),
            '-DownloadPath', (Join-Path $tempRoot 'download'),
            '-NoReboot',
            '-ResumeFromCheckpoint'
        )
    }
)

foreach ($check in $bootstrapChecks) {
    if (-not (Test-Path -LiteralPath $check.Script)) {
        throw "Missing bootstrap entrypoint: $($check.Script)"
    }
    Invoke-SafeBootstrap -Label $check.Label -ScriptPath $check.Script -Arguments $check.Arguments
}

Write-Host "Type check passed for $($trackedFiles.Count) file(s) and $($bootstrapChecks.Count) bootstrap probe(s)." -ForegroundColor Green
exit 0
