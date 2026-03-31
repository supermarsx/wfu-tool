<#
.SYNOPSIS
    Packages the wfu-tool project into a distributable tree and optional ZIP.
.DESCRIPTION
    Stages the runtime scripts, modules, and notices into a versioned output
    directory, validates the staged PowerShell files, and optionally creates a
    ZIP archive plus SHA256 checksum and manifest JSON.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'),
    [switch]$NoZip,
    [switch]$KeepStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent

function Get-WfuGitShortSha {
    try {
        $sha = (& git -C $projectRoot rev-parse --short=7 HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $sha) {
            return $sha.Trim()
        }
    } catch {
    }

    return 'local'
}

function Normalize-WfuPackageVersion {
    param([string]$Value)

    if (-not $Value) {
        return $null
    }

    $text = $Value.Trim()
    if ($text.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $text.Substring(1)
    }

    return $text
}

function Get-WfuPackageId {
    param([string]$Value)

    $normalized = Normalize-WfuPackageVersion $Value
    if (-not $normalized) {
        $normalized = "dev-$((Get-WfuGitShortSha))"
    }

    $safeVersion = ($normalized -replace '[^A-Za-z0-9._-]', '-')
    if ($safeVersion -match '^\d{2}\.\d+$') {
        return [pscustomobject]@{
            Version     = $normalized
            Tag         = "v$normalized"
            PackageName = "wfu-tool-v$normalized"
            IsRelease   = $true
        }
    }

    return [pscustomobject]@{
        Version     = $normalized
        Tag         = $null
        PackageName = "wfu-tool-$safeVersion"
        IsRelease   = $false
    }
}

function New-WfuFileRecord {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullName
    )

    $item = Get-Item -LiteralPath $FullName
    $relative = $item.FullName.Substring($BasePath.Length).TrimStart('\', '/')
    $relative = ($relative -replace '\\', '/')

    [pscustomobject]@{
        Path      = $relative
        SizeBytes  = [int64]$item.Length
        Sha256     = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Copy-WfuPackageItem {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing required package asset: $SourcePath"
    }

    $parent = Split-Path $DestinationPath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Copy-WfuPackageTree {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Missing required package directory: $SourcePath"
    }

    $parent = Split-Path $DestinationPath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $parent -Recurse -Force
}

function Assert-WfuPackageScriptTree {
    param([Parameter(Mandatory)][string]$PackageRoot)

    $parseTargets = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File |
        Where-Object { $_.Extension -in '.ps1', '.psm1' }
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($target in $parseTargets) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($target.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            foreach ($err in $parseErrors) {
                $errors.Add("$($target.FullName): line $($err.Extent.StartLineNumber): $($err.Message)")
            }
        }

        $content = Get-Content -LiteralPath $target.FullName -Raw
        $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]')
        if ($nonAscii.Count -gt 0) {
            $errors.Add("$($target.FullName): contains $($nonAscii.Count) non-ASCII characters")
        }
    }

    if ($errors.Count -gt 0) {
        throw ($errors -join [Environment]::NewLine)
    }
}

function Get-WfuPackageInventory {
    param([Parameter(Mandatory)][string]$PackageRoot)

    $files = Get-ChildItem -LiteralPath $PackageRoot -File -Recurse |
        Sort-Object FullName |
        ForEach-Object { New-WfuFileRecord -BasePath $PackageRoot -FullName $_.FullName }

    $totalBytes = [int64](($files | Measure-Object -Property SizeBytes -Sum).Sum)

    [pscustomobject]@{
        Files      = @($files)
        FileCount  = $files.Count
        TotalBytes = $totalBytes
    }
}

$package = Get-WfuPackageId -Value $Version
$stagingRoot = Join-Path $OutputRoot 'staging'
$packageRoot = Join-Path $stagingRoot $package.PackageName
$zipPath = Join-Path $OutputRoot "$($package.PackageName).zip"
$shaPath = Join-Path $OutputRoot "$($package.PackageName).sha256.txt"
$manifestPath = Join-Path $OutputRoot "$($package.PackageName).manifest.json"

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

foreach ($path in @($packageRoot, $zipPath, $shaPath, $manifestPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

$filesToCopy = @(
    'launch-wfu-tool.bat',
    'launch-wfu-tool.ps1',
    'resume-wfu-tool.ps1',
    'wfu-tool.ps1',
    'wfu-tool-windows-update.ps1',
    'third-party-notices.md',
    'license.md'
)

foreach ($relative in $filesToCopy) {
    Copy-WfuPackageItem -SourcePath (Join-Path $projectRoot $relative) -DestinationPath (Join-Path $packageRoot $relative)
}

Copy-WfuPackageTree -SourcePath (Join-Path $projectRoot 'modules') -DestinationPath (Join-Path $packageRoot 'modules')

Assert-WfuPackageScriptTree -PackageRoot $packageRoot

$inventory = Get-WfuPackageInventory -PackageRoot $packageRoot
$createdUtc = [DateTime]::UtcNow.ToString('o')
$zipHash = $null
if (-not $NoZip) {
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force
    $zipHash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    $zipHash.Hash + "  " + (Split-Path $zipPath -Leaf) | Set-Content -LiteralPath $shaPath -Encoding UTF8
}

$manifest = [pscustomobject]@{
    Version      = $package.Version
    Tag          = $package.Tag
    PackageName  = $package.PackageName
    CreatedUtc   = $createdUtc
    SourceRoot   = $projectRoot
    StagingPath  = $packageRoot
    ZipPath      = if ($NoZip) { $null } else { $zipPath }
    ZipSha256    = if ($zipHash) { $zipHash.Hash } else { $null }
    Sha256Path   = if ($NoZip) { $null } else { $shaPath }
    FileCount    = $inventory.FileCount
    TotalBytes   = $inventory.TotalBytes
    Files        = $inventory.Files
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$result = [pscustomobject]@{
    Version     = $package.Version
    Tag         = $package.Tag
    PackageName = $package.PackageName
    OutputRoot  = $OutputRoot
    StagingPath = $packageRoot
    ZipPath     = if ($NoZip) { $null } else { $zipPath }
    Sha256Path  = if ($NoZip) { $null } else { $shaPath }
    ManifestPath = $manifestPath
    ZipSha256   = if ($zipHash) { $zipHash.Hash } else { $null }
    FileCount   = $inventory.FileCount
    TotalBytes  = $inventory.TotalBytes
    KeptStaging = [bool]$KeepStaging
}

Write-Host ''
Write-Host "  PACKAGED $($result.PackageName)" -ForegroundColor Cyan
Write-Host "  Version   : $($result.Version)" -ForegroundColor DarkGray
Write-Host "  Staging   : $($result.StagingPath)" -ForegroundColor DarkGray
if ($result.ZipPath) {
    Write-Host "  Zip       : $($result.ZipPath)" -ForegroundColor DarkGray
    Write-Host "  SHA256    : $($result.Sha256Path)" -ForegroundColor DarkGray
}
Write-Host "  Manifest  : $($result.ManifestPath)" -ForegroundColor DarkGray
Write-Host "  Files     : $($result.FileCount)" -ForegroundColor DarkGray
Write-Host "  Bytes     : $($result.TotalBytes)" -ForegroundColor DarkGray

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

$result
