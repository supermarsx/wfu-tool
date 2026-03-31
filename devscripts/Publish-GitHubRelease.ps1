<#
.SYNOPSIS
    Create or update a GitHub release and upload release assets.

.DESCRIPTION
    This script is safe to no-op when GitHub credentials or repository context
    are unavailable. It prefers a tag already present on HEAD and will create a
    lightweight tag and release only when needed.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Repository,
    [string]$Token = $(if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }),
    [string]$Version,
    [string]$TagName,
    [string]$ReleaseName,
    [string]$ArtifactRoot,
    [string[]]$ArtifactPath,
    [string]$ChecksumPath,
    [string]$ManifestPath,
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-WfuTruthy {
    param([string]$Value)
    return ($Value -match '^(?i:1|true|yes|on)$')
}

function Test-WfuGitAvailable {
    param([string]$Root)
    try {
        & git -C $Root rev-parse --is-inside-work-tree 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-WfuRepositorySlug {
    param([string]$Root, [string]$ExplicitRepository)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRepository)) {
        return $ExplicitRepository.Trim()
    }

    if ($env:GITHUB_REPOSITORY) {
        return $env:GITHUB_REPOSITORY.Trim()
    }

    if (-not (Test-WfuGitAvailable -Root $Root)) {
        return $null
    }

    $remote = (& git -C $Root remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
        return $null
    }

    $remote = $remote.Trim()
    if ($remote -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/\.]+)(?:\.git)?$') {
        return "$($Matches.owner)/$($Matches.repo)"
    }

    return $null
}

function Invoke-WfuGitHubRest {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter()] $Body,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [string]$ContentType = 'application/json'
    )

    $invokeParams = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $invokeParams.Body = ($Body | ConvertTo-Json -Depth 20)
        $invokeParams.ContentType = $ContentType
    }

    Invoke-RestMethod @invokeParams
}

function Get-WfuGitHubHeaders {
    param([string]$AccessToken)

    return @{
        Authorization          = "Bearer $AccessToken"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Resolve-WfuReleaseArtifacts {
    param(
        [string]$Root,
        [string]$ReleaseVersion,
        [string]$ExplicitArtifactRoot,
        [string[]]$ExplicitArtifactPath,
        [string]$ExplicitChecksumPath,
        [string]$ExplicitManifestPath
    )

    $distRoot = Join-Path $Root 'dist'
    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($path in @($ExplicitArtifactPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            $resolved.Add((Resolve-Path $path).Path)
        }
    }

    foreach ($path in @($ExplicitChecksumPath, $ExplicitManifestPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            $resolved.Add((Resolve-Path $path).Path)
        }
    }

    if ($resolved.Count -gt 0) {
        return @($resolved)
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitArtifactRoot) -and (Test-Path -LiteralPath $ExplicitArtifactRoot)) {
        Get-ChildItem -LiteralPath $ExplicitArtifactRoot -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match "^wfu-tool-v$([regex]::Escape($ReleaseVersion)).*\.(zip|txt|json)$") {
                $resolved.Add($_.FullName)
            }
        }
        if ($resolved.Count -gt 0) {
            return @($resolved | Select-Object -Unique)
        }
    }

    if (Test-Path $distRoot) {
        $patterns = @(
            "wfu-tool-v$ReleaseVersion*.zip",
            "wfu-tool-v$ReleaseVersion*.sha256.txt",
            "wfu-tool-v$ReleaseVersion*.manifest.json"
        )
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $distRoot -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                $resolved.Add($_.FullName)
            }
        }
    }

    return @($resolved | Select-Object -Unique)
}

function Ensure-WfuGitTag {
    param(
        [string]$Root,
        [string]$Tag,
        [string]$Sha,
        [switch]$Push
    )

    $existing = & git -C $Root tag --list $Tag 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        return $true
    }

    & git -C $Root tag $Tag $Sha
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create git tag '$Tag' at $Sha."
    }

    if ($Push) {
        & git -C $Root push origin $Tag
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push git tag '$Tag' to origin."
        }
    }

    return $true
}

function Test-WfuReleaseExists {
    param(
        [string]$Headers,
        [string]$Repo,
        [string]$Tag
    )

    try {
        $null = Invoke-WfuGitHubRest -Method GET -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $Headers
        return $true
    }
    catch {
        return $false
    }
}

function Get-WfuReleaseByTag {
    param(
        [hashtable]$Headers,
        [string]$Repo,
        [string]$Tag
    )

    try {
        return Invoke-WfuGitHubRest -Method GET -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $Headers
    }
    catch {
        return $null
    }
}

function New-WfuRelease {
    param(
        [hashtable]$Headers,
        [string]$Repo,
        [string]$Tag,
        [string]$Name,
        [bool]$Draft,
        [bool]$Prerelease
    )

    $body = @{
        tag_name               = $Tag
        name                   = $Name
        draft                  = $Draft
        prerelease             = $Prerelease
        generate_release_notes = $true
    }

    Invoke-WfuGitHubRest -Method POST -Uri "https://api.github.com/repos/$Repo/releases" -Headers $Headers -Body $body
}

function Add-WfuReleaseAsset {
    param(
        [hashtable]$Headers,
        [string]$UploadUrl,
        [string]$Path
    )

    $fileName = Split-Path $Path -Leaf
    $assetName = [uri]::EscapeDataString($fileName)
    $assetUri = ($UploadUrl -replace '\{\?name,label\}$', '') + "?name=$assetName"
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $headers = @{}
    foreach ($key in $Headers.Keys) {
        $headers[$key] = $Headers[$key]
    }
    $headers['Content-Type'] = 'application/octet-stream'

    try {
        Invoke-RestMethod -Method POST -Uri $assetUri -Headers $headers -Body $bytes -ContentType 'application/octet-stream' -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 422) {
            return [pscustomobject]@{
                Status = 'Skipped'
                Path   = $Path
                Reason = 'Asset already exists'
            }
        }

        throw
    }
}

$repo = Get-WfuRepositorySlug -Root $RepositoryRoot -ExplicitRepository $Repository
if ([string]::IsNullOrWhiteSpace($repo)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'Repository context not available'
        Repository = $null
        Version    = $Version
        TagName    = $TagName
        ReleaseUrl = $null
        Assets     = @()
    }
    if ($PassThru) { $result }
    return
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'GitHub token not available'
        Repository = $repo
        Version    = $Version
        TagName    = $TagName
        ReleaseUrl = $null
        Assets     = @()
    }
    if ($PassThru) { $result }
    return
}

if ([string]::IsNullOrWhiteSpace($Version) -or [string]::IsNullOrWhiteSpace($TagName)) {
    $releaseInfo = & (Join-Path $PSScriptRoot 'Get-ReleaseVersion.ps1') -RepositoryRoot $RepositoryRoot
    if ($releaseInfo.Status -ne 'Resolved') {
        $result = [pscustomobject]@{
            Status     = 'Skipped'
            Reason     = 'Unable to resolve release version'
            Repository = $repo
            Version    = $Version
            TagName    = $TagName
            ReleaseUrl = $null
            Assets     = @()
        }
        if ($PassThru) { $result }
        return
    }

    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $releaseInfo.Version }
    if ([string]::IsNullOrWhiteSpace($TagName)) { $TagName = $releaseInfo.TagName }
}

if ([string]::IsNullOrWhiteSpace($ReleaseName)) {
    $ReleaseName = $Version
}

$artifactList = Resolve-WfuReleaseArtifacts -Root $RepositoryRoot -ReleaseVersion $Version -ExplicitArtifactRoot $ArtifactRoot -ExplicitArtifactPath $ArtifactPath -ExplicitChecksumPath $ChecksumPath -ExplicitManifestPath $ManifestPath
if (-not $artifactList -or $artifactList.Count -eq 0) {
    $result = [pscustomobject]@{
        Status     = 'Skipped'
        Reason     = 'No release artifacts found'
        Repository = $repo
        Version    = $Version
        TagName    = $TagName
        ReleaseUrl = $null
        Assets     = @()
    }
    if ($PassThru) { $result }
    return
}

$headers = Get-WfuGitHubHeaders -AccessToken $Token
$sha = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
Ensure-WfuGitTag -Root $RepositoryRoot -Tag $TagName -Sha $sha -Push

$release = Get-WfuReleaseByTag -Headers $headers -Repo $repo -Tag $TagName
if (-not $release) {
    $release = New-WfuRelease -Headers $headers -Repo $repo -Tag $TagName -Name $ReleaseName -Draft ([bool]$Draft) -Prerelease ([bool]$Prerelease)
}

$uploaded = @()
foreach ($asset in $artifactList) {
    $assetName = Split-Path $asset -Leaf
    $alreadyExists = $false
    foreach ($releaseAsset in @($release.assets)) {
        if ($releaseAsset.name -eq $assetName) {
            $alreadyExists = $true
            break
        }
    }

    if ($alreadyExists) {
        $uploaded += [pscustomobject]@{ Status = 'Skipped'; Path = $asset; Reason = 'Asset already present' }
        continue
    }

    $uploaded += Add-WfuReleaseAsset -Headers $headers -UploadUrl $release.upload_url -Path $asset
}

$output = [pscustomobject]@{
    Status     = 'Published'
    Repository = $repo
    Version    = $Version
    TagName    = $TagName
    ReleaseUrl = $release.html_url
    UploadUrl  = $release.upload_url
    Assets     = $uploaded
}

if ($PassThru) {
    $output
}
