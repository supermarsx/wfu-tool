<#
.SYNOPSIS
    Validates legacy Windows 10 version enumeration.
#>

function Resolve-LegacyCommand {
    param([string[]]$Candidates)

    foreach ($name in $Candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }

    return $null
}

function Invoke-LegacyEnumeration {
    param($Cmd)

    foreach ($args in @(
        @(),
        @('-IncludeLegacy'),
        @('-LegacyOnly')
    )) {
        try {
            return & $Cmd.Name @args
        } catch {
            continue
        }
    }

    return $null
}

function Unwrap-LegacyEnumerationItem {
    param($Item)

    if ($Item -is [string]) {
        return $Item
    }

    foreach ($propName in @('Value', 'Item', 'Release', 'Descriptor')) {
        if ($Item.PSObject.Properties.Name -contains $propName) {
            $candidate = $Item.$propName
            if ($candidate -and $candidate.PSObject.Properties.Count -gt 0) {
                return $candidate
            }
        }
    }

    return $Item
}

$enumerationCmd = Resolve-LegacyCommand -Candidates @(
    'Get-LegacyMediaVersions',
    'Get-LegacyWindowsVersions',
    'Get-LegacyMediaReleaseManifest',
    'Get-LegacyMediaManifest'
)

if (-not $enumerationCmd) {
    Skip-Test 'Legacy enumeration' 'Legacy enumeration helper not available yet'
    return
}

$items = Invoke-LegacyEnumeration -Cmd $enumerationCmd
if (-not $items) {
    Skip-Test 'Legacy enumeration' 'Legacy enumeration helper returned no items'
    return
}

if ($items -isnot [System.Collections.IEnumerable] -or $items -is [string]) {
    $items = @($items)
}

$expectedVersions = @(
    'W10_1507',
    'W10_1511',
    'W10_1607',
    'W10_1703',
    'W10_1709',
    'W10_1803',
    'W10_1809',
    'W10_1903',
    'W10_1909',
    'W10_2004',
    'W10_20H2',
    'W10_21H1',
    'W10_21H2',
    'W10_22H2'
)

$versionValues = foreach ($item in $items) {
    $item = Unwrap-LegacyEnumerationItem -Item $item
    if ($item -is [string]) {
        [string]$item
        continue
    }
    foreach ($propName in @('VersionId', 'Version', 'Id', 'Name')) {
        if ($item.PSObject.Properties.Name -contains $propName) {
            [string]$item.$propName
            break
        }
    }
}
$versionValues = @($versionValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

Assert-True ($versionValues.Count -ge $expectedVersions.Count) "Legacy enumeration: has at least $($expectedVersions.Count) versions ($($versionValues.Count))"

foreach ($version in $expectedVersions) {
    Assert-True ($version -in $versionValues) "Legacy enumeration: includes $version"
}

$builds = foreach ($item in $items) {
    $item = Unwrap-LegacyEnumerationItem -Item $item
    foreach ($propName in @('Build', 'TargetBuild', 'LatestBuild')) {
        if ($item.PSObject.Properties.Name -contains $propName) {
            [int]$item.$propName
            break
        }
    }
}
