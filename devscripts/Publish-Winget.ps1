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
    [string]$PackageIdentifier = 'supermarsx.wfu-tool',
    [string]$PackageName = 'wfu-tool',
    [string]$Publisher = 'supermarsx',
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
        $trimmed = $ExplicitUrl.Trim()
        if ($trimmed -match '^https?://') {
            return $trimmed
        }
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

function ConvertTo-WfuYamlScalar {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return "''" }
    $text = [string]$Value
    $escaped = $text -replace "'", "''"
    return "'$escaped'"
}

function Get-WfuWingetConfig {
    param([string]$Root)

    $configPath = Join-Path $Root 'packaging\winget\winget-config.psd1'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @{}
    }

    $config = Import-PowerShellDataFile -LiteralPath $configPath
    if ($config -is [hashtable]) {
        return $config
    }

    return @{}
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

$wingetConfig = Get-WfuWingetConfig -Root $RepositoryRoot
if ($wingetConfig.PackageIdentifier) { $PackageIdentifier = [string]$wingetConfig.PackageIdentifier }
if ($wingetConfig.PackageName) { $PackageName = [string]$wingetConfig.PackageName }
if ($wingetConfig.Publisher) { $Publisher = [string]$wingetConfig.Publisher }

$publisherUrl = if ($wingetConfig.PublisherUrl) { [string]$wingetConfig.PublisherUrl } else { $null }
$publisherSupportUrl = if ($wingetConfig.PublisherSupportUrl) { [string]$wingetConfig.PublisherSupportUrl } else { $null }
$packageUrl = if ($wingetConfig.PackageUrl) { [string]$wingetConfig.PackageUrl } else { $null }
$license = if ($wingetConfig.License) { [string]$wingetConfig.License } else { 'MIT' }
$licenseUrl = if ($wingetConfig.LicenseUrl) { [string]$wingetConfig.LicenseUrl } else { $null }
$shortDescription = if ($wingetConfig.ShortDescription) { [string]$wingetConfig.ShortDescription } else { 'Windows feature upgrade helper' }
$description = if ($wingetConfig.Description) { [string]$wingetConfig.Description } else { $shortDescription }
$moniker = if ($wingetConfig.Moniker) { [string]$wingetConfig.Moniker } else { $null }
$manifestVersion = if ($wingetConfig.ManifestVersion) { [string]$wingetConfig.ManifestVersion } else { '1.6.0' }
$installerType = if ($wingetConfig.InstallerType) { [string]$wingetConfig.InstallerType } else { 'zip' }
$nestedInstallerType = if ($wingetConfig.NestedInstallerType) { [string]$wingetConfig.NestedInstallerType } else { $null }
$releaseNotesUrl = if ($wingetConfig.ReleaseNotesUrl) { [string]$wingetConfig.ReleaseNotesUrl } else { $null }
$tags = @()
foreach ($tag in @($wingetConfig.Tags)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$tag)) {
        $tags += [string]$tag
    }
}
$nestedInstallerFiles = @($wingetConfig.NestedInstallerFiles)

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

$installerYaml = New-Object System.Collections.Generic.List[string]
$installerYaml.Add("PackageIdentifier: $PackageIdentifier") | Out-Null
$installerYaml.Add("PackageVersion: $Version") | Out-Null
$installerYaml.Add('Platform:') | Out-Null
$installerYaml.Add('  - Windows.Desktop') | Out-Null
$installerYaml.Add("InstallerType: $installerType") | Out-Null
if ($nestedInstallerType) {
    $installerYaml.Add("NestedInstallerType: $nestedInstallerType") | Out-Null
}
$installerYaml.Add('InstallModes:') | Out-Null
$installerYaml.Add('  - interactive') | Out-Null
$installerYaml.Add('Installers:') | Out-Null
$installerYaml.Add('  - Architecture: x64') | Out-Null
$installerYaml.Add("    InstallerUrl: $ReleaseUrl") | Out-Null
$installerYaml.Add("    InstallerSha256: $(if ($InstallerSha256) { $InstallerSha256.ToUpperInvariant() } else { '0000000000000000000000000000000000000000000000000000000000000000' })") | Out-Null
$installerYaml.Add('    Scope: machine') | Out-Null
foreach ($nested in $nestedInstallerFiles) {
    if (-not $nested) { continue }
    $relativeFilePath = if ($nested.RelativeFilePath) { [string]$nested.RelativeFilePath } else { $null }
    if (-not $relativeFilePath) { continue }
    $installerYaml.Add('    NestedInstallerFiles:') | Out-Null
    $installerYaml.Add("      - RelativeFilePath: $relativeFilePath") | Out-Null
    if ($nested.PortableCommandAlias) {
        $installerYaml.Add("        PortableCommandAlias: $($nested.PortableCommandAlias)") | Out-Null
    }
    break
}
$installerYaml.Add('ManifestType: installer') | Out-Null
$installerYaml.Add("ManifestVersion: $manifestVersion") | Out-Null

$versionYaml = @(
    "PackageIdentifier: $PackageIdentifier"
    "PackageVersion: $Version"
    'DefaultLocale: en-US'
    'ManifestType: version'
    "ManifestVersion: $manifestVersion"
)

$localeYaml = New-Object System.Collections.Generic.List[string]
$localeYaml.Add("PackageIdentifier: $PackageIdentifier") | Out-Null
$localeYaml.Add("PackageVersion: $Version") | Out-Null
$localeYaml.Add('PackageLocale: en-US') | Out-Null
$localeYaml.Add("Publisher: $(ConvertTo-WfuYamlScalar $Publisher)") | Out-Null
$localeYaml.Add("PackageName: $(ConvertTo-WfuYamlScalar $PackageName)") | Out-Null
$localeYaml.Add("ShortDescription: $(ConvertTo-WfuYamlScalar $shortDescription)") | Out-Null
$localeYaml.Add("Description: $(ConvertTo-WfuYamlScalar $description)") | Out-Null
$localeYaml.Add("License: $(ConvertTo-WfuYamlScalar $license)") | Out-Null
if ($publisherUrl) { $localeYaml.Add("PublisherUrl: $publisherUrl") | Out-Null }
if ($publisherSupportUrl) { $localeYaml.Add("PublisherSupportUrl: $publisherSupportUrl") | Out-Null }
if ($packageUrl) { $localeYaml.Add("PackageUrl: $packageUrl") | Out-Null }
if ($licenseUrl) { $localeYaml.Add("LicenseUrl: $licenseUrl") | Out-Null }
if ($moniker) { $localeYaml.Add("Moniker: $moniker") | Out-Null }
if ($releaseNotesUrl) { $localeYaml.Add("ReleaseNotesUrl: $releaseNotesUrl") | Out-Null }
if ($tags.Count -gt 0) {
    $localeYaml.Add('Tags:') | Out-Null
    foreach ($tag in $tags) {
        $localeYaml.Add("  - $tag") | Out-Null
    }
}
$localeYaml.Add('ManifestType: defaultLocale') | Out-Null
$localeYaml.Add("ManifestVersion: $manifestVersion") | Out-Null
Set-Content -LiteralPath $installerManifest -Value $installerYaml -Encoding UTF8
Set-Content -LiteralPath $versionManifest -Value $versionYaml -Encoding UTF8
Set-Content -LiteralPath $localeManifest -Value $localeYaml -Encoding UTF8

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
        }
        catch {
            # Keep the script safe to no-op when PR automation is not available.
        }
    }
}

if ($PassThru) {
    $result
}
