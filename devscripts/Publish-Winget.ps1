<#
.SYNOPSIS
    Scaffold or publish winget manifests for wfu-tool.

.DESCRIPTION
    The script is disabled unless ENABLE_WINGET is truthy and a token is
    available. Without those inputs, it safely no-ops and emits a skipped
    status object.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Version,
    [string]$PackageIdentifier = 'wfu-tool',
    [string]$PackageName = 'wfu-tool',
    [string]$Publisher = 'wfu-tool',
    [string]$ReleaseUrl,
    [string]$InstallerUrl,
    [string]$InstallerSha256,
    [string]$TargetRepository = 'microsoft/winget-pkgs',
    [string]$Token = $env:WINGET_GITHUB_TOKEN,
    [string]$ArtifactRoot,
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\winget'),
    [switch]$CreatePullRequest,
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

function Get-WfuSha256 {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return $null
    }

    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Resolve-WfuPackageArtifact {
    param(
        [string]$Root,
        [string]$ReleaseVersion
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $Root -File -Filter "wfu-tool-v$ReleaseVersion.zip" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-WfuTruthy -Value $env:ENABLE_WINGET)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Winget publishing disabled'
        OutputRoot = $OutputRoot
        Manifests  = @()
        CreatedPR  = $null
    }
    if ($PassThru) { $result }
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Winget token not available'
        OutputRoot = $OutputRoot
        Manifests  = @()
        CreatedPR  = $null
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

if ([string]::IsNullOrWhiteSpace($InstallerUrl) -and -not [string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $InstallerUrl = Resolve-WfuPackageArtifact -Root $ArtifactRoot -ReleaseVersion $Version
}

if ([string]::IsNullOrWhiteSpace($ReleaseUrl)) {
    $ReleaseUrl = Get-WfuSourceUrl -ExplicitUrl $InstallerUrl -Release $Version
}

if ([string]::IsNullOrWhiteSpace($InstallerSha256) -and -not [string]::IsNullOrWhiteSpace($InstallerUrl) -and (Test-Path -LiteralPath $InstallerUrl)) {
    $InstallerSha256 = Get-WfuSha256 -Path $InstallerUrl
}

if ([string]::IsNullOrWhiteSpace($ReleaseUrl) -or [string]::IsNullOrWhiteSpace($Version)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Missing version or release URL'
        OutputRoot = $OutputRoot
        Manifests  = @()
        CreatedPR  = $null
    }
    if ($PassThru) { $result }
    return
}

$manifestRoot = Join-Path $OutputRoot $Version
$installerManifestDir = Join-Path $manifestRoot 'manifests\installer'
$localeManifestDir = Join-Path $manifestRoot 'manifests\locale'
New-Item -ItemType Directory -Force -Path $installerManifestDir, $localeManifestDir | Out-Null

$installerManifest = Join-Path $installerManifestDir "$PackageIdentifier.installer.yaml"
$versionManifest = Join-Path $manifestRoot 'version.yaml'
$localeManifest = Join-Path $localeManifestDir "$PackageIdentifier.locale.en-US.yaml"

$installerContent = @"
PackageIdentifier: $PackageIdentifier
PackageVersion: $Version
PackageLocale: en-US
Publisher: $Publisher
PackageName: $PackageName
License: MIT
ShortDescription: Windows feature upgrade helper
InstallerType: exe
InstallModes:
  - interactive
  - silent
InstallerSwitches:
  Silent: /quiet
  SilentWithProgress: /quiet
Installers:
  - Architecture: x64
    InstallerUrl: $ReleaseUrl
    InstallerSha256: $(if ($InstallerSha256) { $InstallerSha256 } else { '0000000000000000000000000000000000000000000000000000000000000000' })
    Scope: machine
"@

$versionContent = @"
PackageIdentifier: $PackageIdentifier
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.6.0
"@

$localeContent = @"
PackageIdentifier: $PackageIdentifier
PackageVersion: $Version
PackageLocale: en-US
Publisher: $Publisher
PackageName: $PackageName
ShortDescription: Windows feature upgrade helper
License: MIT
ManifestType: defaultLocale
ManifestVersion: 1.6.0
"@

Set-Content -LiteralPath $installerManifest -Value $installerContent -Encoding UTF8
Set-Content -LiteralPath $versionManifest -Value $versionContent -Encoding UTF8
Set-Content -LiteralPath $localeManifest -Value $localeContent -Encoding UTF8

$result = [pscustomobject]@{
    Status     = 'Scaffolded'
    Reason     = 'Winget manifests generated locally'
    OutputRoot = $manifestRoot
    Manifests  = @($versionManifest, $installerManifest, $localeManifest)
    CreatedPR  = $null
}

if ($CreatePullRequest -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    $branchName = "codex/winget-$Version"
    $repoRoot = $RepositoryRoot
    $gitRepo = $env:GITHUB_REPOSITORY
    if (-not [string]::IsNullOrWhiteSpace($gitRepo)) {
        try {
            & gh auth status --hostname github.com 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $prTitle = "Add $PackageIdentifier $Version to winget"
                $prBody = "Generated winget manifests for $PackageIdentifier $Version.`n`nRelease: $ReleaseUrl"
                & gh pr create --repo $TargetRepository --title $prTitle --body $prBody --head "$gitRepo`:$branchName" --base master 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $result = [pscustomobject]@{
                        Status     = 'Scaffolded'
                        Reason     = 'Winget manifests generated locally; PR request attempted'
                        OutputRoot = $manifestRoot
                        Manifests  = @($versionManifest, $installerManifest, $localeManifest)
                        CreatedPR  = $true
                    }
                }
            }
        } catch {
            # Keep the script safe to no-op when PR automation is not available.
        }
    }
}

if ($PassThru) {
    $result
}
