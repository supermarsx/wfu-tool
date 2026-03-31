# Tests for legacy Windows 10 media scaffolding

Write-Host '    (Legacy media discovery tests skip until the new helpers are available)' -ForegroundColor DarkGray

$expectedVersions = @(
    'W10_1507', 'W10_1511', 'W10_1607', 'W10_1703', 'W10_1709',
    'W10_1803', 'W10_1809', 'W10_1903', 'W10_1909', 'W10_2004',
    'W10_20H2', 'W10_21H1', 'W10_21H2', 'W10_22H2'
)

$legacyManifestCommand = @(
    'Get-LegacyMediaManifest',
    'Get-LegacyMediaReleaseSpecs'
    'Get-LegacyMediaVersions'
) | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

$legacySpecCommand = Get-Command 'Get-LegacyMediaReleaseSpec' -ErrorAction SilentlyContinue

if (-not $legacyManifestCommand -and -not $legacySpecCommand) {
    Skip-Test 'LegacyMedia: helper availability' 'Legacy media manifest helper not implemented yet'
    return
}

function Get-LegacyEntry {
    param(
        $Manifest,
        [string]$Version
    )

    if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains($Version)) {
            return $Manifest[$Version]
        }
    }

    $collection = @()
    if ($Manifest.PSObject.Properties.Name -contains 'Versions') {
        $collection = @($Manifest.Versions)
    } else {
        $collection = @($Manifest)
    }

    return $collection | Where-Object {
        (($_.PSObject.Properties.Name -contains 'Version') -and $_.Version -eq $Version) -or
        (($_.PSObject.Properties.Name -contains 'VersionId') -and $_.VersionId -eq $Version) -or
        (($_.PSObject.Properties.Name -contains 'Name') -and $_.Name -eq $Version)
    } | Select-Object -First 1
}

if ($legacyManifestCommand) {
    $manifest = & $legacyManifestCommand
    Assert-NotNull $manifest 'LegacyMedia: Manifest returned'
}

if (-not $legacyManifestCommand -and $legacySpecCommand) {
    $manifest = $null
}

if ($legacyManifestCommand -and -not $manifest) {
    return
}

foreach ($version in $expectedVersions) {
    if ($legacySpecCommand) {
        $entry = & $legacySpecCommand -Version $version
    } else {
        $entry = Get-LegacyEntry -Manifest $manifest -Version $version
    }
    if (($entry -is [string]) -and $legacySpecCommand) {
        $entry = & $legacySpecCommand -Version $entry
    }
    Assert-NotNull $entry "LegacyMedia[$version]: Entry exists"

    if ($entry) {
        Assert-True ($entry.Build -gt 10000) "LegacyMedia[$version]: Build is set"
        Assert-NotNull $entry.DisplayVersion "LegacyMedia[$version]: DisplayVersion is set"

        $sourceFields = @(
            'ProductsCabUrl',
            'ProductsXmlUrl',
            'MctUrl',
            'MctUrl32',
            'MctExeUrl',
            'CatalogUrl',
            'SourceUrl',
            'Url'
        )
        $hasSourceField = $false
        foreach ($field in $sourceFields) {
            if ($entry.PSObject.Properties.Name -contains $field -and $entry.$field) {
                $hasSourceField = $true
                break
            }
        }
        Assert-True $hasSourceField "LegacyMedia[$version]: Has a catalog or executable source URL"
    }
}
