<#
.SYNOPSIS
    Computes the next YY.N release version or reuses the version already tagged on HEAD.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = $(if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { (Get-Location).Path })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-WfuReleaseTag {
    param([Parameter(Mandatory)][string]$Tag)

    if ($Tag -notmatch '^v(?<Year>\d{2})\.(?<Counter>\d+)$') {
        return $null
    }

    [pscustomobject]@{
        Tag     = $Tag
        Year    = $matches.Year
        Counter = [int]$matches.Counter
    }
}

if (-not (Test-Path -LiteralPath $RepositoryRoot)) {
    throw "Repository root not found: $RepositoryRoot"
}

$utcYear = [DateTime]::UtcNow.ToString('yy')
$headSha = $null
$shortSha = $null
$source = 'Computed'

try {
    $headSha = & git -C $RepositoryRoot rev-parse --verify HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $headSha) {
        throw 'Unable to read HEAD commit'
    }

    $shortSha = & git -C $RepositoryRoot rev-parse --short=7 HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $shortSha) {
        throw 'Unable to read short HEAD commit'
    }
}
catch {
    $headSha = $null
    $shortSha = 'local'
    $source = 'Fallback'
}

$headTags = @()
try {
    $headTagLines = & git -C $RepositoryRoot tag --points-at HEAD --list "v$utcYear.*" 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($tagLine in @($headTagLines)) {
            $parsed = ConvertFrom-WfuReleaseTag -Tag ([string]$tagLine).Trim()
            if ($parsed -and $parsed.Year -eq $utcYear) {
                $headTags += $parsed
            }
        }
    }
}
catch {
    $headTags = @()
}

if ($headTags.Count -gt 0) {
    $selected = $headTags | Sort-Object Counter -Descending | Select-Object -First 1
    $existingTags = @($headTags | ForEach-Object { $_.Tag })
    [pscustomobject]@{
        Status       = 'Resolved'
        Year         = $utcYear
        Counter      = $selected.Counter
        Version      = "$utcYear.$($selected.Counter)"
        Tag          = $selected.Tag
        TagName      = $selected.Tag
        Commit       = $headSha
        CommitShort  = $shortSha
        Source       = 'CommitTag'
        Reused       = $true
        ExistingTag  = $selected.Tag
        ExistingTags = $existingTags
    }
    return
}

$yearTags = @()
try {
    $tagLines = & git -C $RepositoryRoot tag --list "v$utcYear.*" 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($tagLine in @($tagLines)) {
            $parsed = ConvertFrom-WfuReleaseTag -Tag ([string]$tagLine).Trim()
            if ($parsed -and $parsed.Year -eq $utcYear) {
                $yearTags += $parsed
            }
        }
    }
}
catch {
    $yearTags = @()
}

$nextCounter = 1
if ($yearTags.Count -gt 0) {
    $maxCounter = ($yearTags | Measure-Object -Property Counter -Maximum).Maximum
    if ($maxCounter) {
        $nextCounter = ([int]$maxCounter) + 1
    }
}

$version = "$utcYear.$nextCounter"
$tagName = "v$version"

[pscustomobject]@{
    Status       = 'Resolved'
    Year         = $utcYear
    Counter      = $nextCounter
    Version      = $version
    Tag          = $tagName
    TagName      = $tagName
    Commit       = $headSha
    CommitShort  = $shortSha
    Source       = $source
    Reused       = $false
    ExistingTag  = $null
    ExistingTags = @($yearTags | ForEach-Object { $_.Tag })
}
