<#
.SYNOPSIS
    Build or publish the Chocolatey package for wfu-tool.

.DESCRIPTION
    The script is disabled unless ENABLE_CHOCO is truthy and CHOCO_API_KEY is
    present. Without those inputs, it safely no-ops and returns a skipped
    status object.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Version,
    [string]$PackageUrl,
    [string]$ChecksumUrl,
    [string]$PackageId = 'wfu-tool',
    [string]$ArtifactRoot,
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\chocolatey'),
    [string]$Token = $env:CHOCO_API_KEY,
    [switch]$Push,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WfuTruthy {
    param([string]$Value)
    return ($Value -match '^(?i:1|true|yes|on)$')
}

function Get-WfuSourceUrl {
    param([string]$ExplicitUrl, [string]$Release)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) {
        return $ExplicitUrl.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($Release)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_REPOSITORY)) {
        return $null
    }

    return "https://github.com/$($env:GITHUB_REPOSITORY)/releases/download/v$Release/wfu-tool-v$Release.zip"
}

function Resolve-WfuArtifactChecksumUrl {
    param(
        [string]$Root,
        [string]$ReleaseVersion
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $checksumFile = Get-ChildItem -LiteralPath $Root -File -Filter "wfu-tool-v$ReleaseVersion.sha256.txt" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($checksumFile) {
        return $checksumFile.FullName
    }

    return $null
}

if (-not (Test-WfuTruthy -Value $env:ENABLE_CHOCO)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Chocolatey publishing disabled'
        Package    = $null
        PackageId  = $PackageId
        OutputRoot = $OutputRoot
        Published  = $false
    }
    if ($PassThru) { $result }
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Chocolatey API key not available'
        Package    = $null
        PackageId  = $PackageId
        OutputRoot = $OutputRoot
        Published  = $false
    }
    if ($PassThru) { $result }
    return
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionInfo = & (Join-Path $PSScriptRoot 'Get-ReleaseVersion.ps1') -RepositoryRoot $RepositoryRoot
    if ($versionInfo.Status -eq 'Resolved') {
        $Version = $versionInfo.Version
    }
}

if ([string]::IsNullOrWhiteSpace($PackageUrl)) {
    $PackageUrl = Get-WfuSourceUrl -ExplicitUrl $PackageUrl -Release $Version
}

if ([string]::IsNullOrWhiteSpace($ChecksumUrl) -and -not [string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $ChecksumUrl = Resolve-WfuArtifactChecksumUrl -Root $ArtifactRoot -ReleaseVersion $Version
}

if ([string]::IsNullOrWhiteSpace($Version) -or [string]::IsNullOrWhiteSpace($PackageUrl)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Missing version or package URL'
        Package    = $null
        PackageId  = $PackageId
        OutputRoot = $OutputRoot
        Published  = $false
    }
    if ($PassThru) { $result }
    return
}

$packageRoot = Join-Path $OutputRoot $Version
$toolsDir = Join-Path $packageRoot 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

$sourceNuspec = Join-Path $RepositoryRoot 'packaging\chocolatey\wfu-tool.nuspec'
$sourceInstall = Join-Path $RepositoryRoot 'packaging\chocolatey\tools\chocolateyinstall.ps1'
if (Test-Path $sourceNuspec) {
    Copy-Item -LiteralPath $sourceNuspec -Destination (Join-Path $packageRoot "$PackageId.nuspec") -Force
}
if (Test-Path $sourceInstall) {
    Copy-Item -LiteralPath $sourceInstall -Destination (Join-Path $toolsDir 'chocolateyinstall.ps1') -Force
}

$nuspecPath = Join-Path $packageRoot "$PackageId.nuspec"
$nuspecContent = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>$PackageId</id>
    <version>$Version</version>
    <title>wfu-tool</title>
    <authors>wfu-tool</authors>
    <owners>wfu-tool</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>Windows feature upgrade helper</description>
    <projectUrl>https://github.com/$env:GITHUB_REPOSITORY</projectUrl>
    <copyright>Copyright (c) wfu-tool</copyright>
    <tags>windows upgrade installer</tags>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
"@

Set-Content -LiteralPath $nuspecPath -Value $nuspecContent -Encoding UTF8

$nupkgPath = Join-Path $OutputRoot "$PackageId.$Version.nupkg"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
if (Test-Path $nupkgPath) {
    Remove-Item -LiteralPath $nupkgPath -Force
}

Push-Location $packageRoot
try {
    $tempZip = Join-Path $packageRoot "$PackageId.$Version.zip"
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    Compress-Archive -Path (Join-Path $packageRoot "$PackageId.nuspec"), (Join-Path $packageRoot 'tools') -DestinationPath $tempZip -Force
    Copy-Item -LiteralPath $tempZip -Destination $nupkgPath -Force
}
finally {
    Pop-Location
}

$published = $false
if ($Push -and (Get-Command choco -ErrorAction SilentlyContinue)) {
    & choco push $nupkgPath --source https://push.chocolatey.org/ --api-key $Token
    if ($LASTEXITCODE -eq 0) {
        $published = $true
    }
}

$result = [pscustomobject]@{
    Status      = $(if ($published) { 'Published' } else { 'Built' })
    Reason      = $(if ($published) { 'Chocolatey push succeeded' } else { 'Chocolatey package built locally' })
    Package     = $nupkgPath
    PackageId   = $PackageId
    OutputRoot  = $packageRoot
    Published   = $published
    PackageUrl  = $PackageUrl
    ChecksumUrl = $ChecksumUrl
}

if ($PassThru) {
    $result
}
