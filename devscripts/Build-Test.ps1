<#
.SYNOPSIS
    Builds the distributable tree in staging and validates the packaged output.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputRoot,
    [switch]$KeepStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputRoot) {
    $OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wfu-build-test-{0}" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}

$packageScript = Join-Path $PSScriptRoot 'Package.ps1'
if (-not (Test-Path -LiteralPath $packageScript)) {
    throw "Package script not found: $packageScript"
}

$packageArgs = @{
    NoZip       = $true
    KeepStaging = $true
    OutputRoot  = $OutputRoot
}
if ($Version) {
    $packageArgs.Version = $Version
}

$package = & $packageScript @packageArgs | Select-Object -Last 1
if (-not $package -or -not $package.StagingPath) {
    throw 'Package script did not return a staging path.'
}

$stagingPath = $package.StagingPath
if (-not (Test-Path -LiteralPath $stagingPath)) {
    throw "Staging path not found: $stagingPath"
}

$requiredPaths = @(
    'launch-wfu-tool.bat',
    'launch-wfu-tool.ps1',
    'resume-wfu-tool.ps1',
    'wfu-tool.ps1',
    'wfu-tool-windows-update.ps1',
    'modules',
    'modules\Upgrade\Automation.ps1',
    'modules\Upgrade\LegacyMedia.ps1',
    'modules\Upgrade\MediaTools.ps1',
    'third-party-notices.md',
    'license.md',
    'wfu-tool.ps1'
)

foreach ($relative in $requiredPaths) {
    $candidate = Join-Path $stagingPath $relative
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Packaged file missing: $relative"
    }
}

$parseTargets = Get-ChildItem -LiteralPath $stagingPath -Recurse -Include *.ps1, *.psm1
foreach ($target in $parseTargets) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($target.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $messages = $parseErrors | ForEach-Object {
            "line $($_.Extent.StartLineNumber): $($_.Message)"
        }
        throw "Parse failure in $($target.Name): $(($messages -join '; '))"
    }
}

$manifestPath = $package.ManifestPath
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest file missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.Version -ne $package.Version) {
    throw "Manifest version mismatch: expected $($package.Version), got $($manifest.Version)"
}

if ($manifest.PackageName -ne $package.PackageName) {
    throw "Manifest package mismatch: expected $($package.PackageName), got $($manifest.PackageName)"
}

$oldTestMode = $env:WFU_TOOL_TEST_MODE
$env:WFU_TOOL_TEST_MODE = '1'
try {
    . (Join-Path $stagingPath 'wfu-tool.ps1') -TargetVersion '25H2' -NoReboot `
        -LogPath (Join-Path $stagingPath 'build-test.log') `
        -DownloadPath (Join-Path $stagingPath 'downloads') `
        -SkipBypasses -SkipBlockerRemoval -SkipTelemetry -SkipRepair `
        -SkipCumulativeUpdates -SkipNetworkCheck -SkipDiskCheck -MaxRetries 1
}
finally {
    $env:WFU_TOOL_TEST_MODE = $oldTestMode
}

$result = [pscustomobject]@{
    Version      = $package.Version
    PackageName  = $package.PackageName
    OutputRoot   = $OutputRoot
    StagingPath  = $stagingPath
    ManifestPath = $manifestPath
    ParsedFiles  = $parseTargets.Count
    KeptStaging  = [bool]$KeepStaging
}

Write-Host ''
Write-Host "  BUILD TEST PASSED: $($result.PackageName)" -ForegroundColor Green
Write-Host "  Staging : $($result.StagingPath)" -ForegroundColor DarkGray
Write-Host "  Parsed  : $($result.ParsedFiles) file(s)" -ForegroundColor DarkGray

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

$result
