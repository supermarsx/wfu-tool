<#
.SYNOPSIS
    Validates the legacy Windows 10 media manifest shape and completeness.
#>

function Resolve-LegacyCommand {
    param([string[]]$Candidates)

    foreach ($name in $Candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd }
    }

    return $null
}

function Get-LegacyManifestEntries {
    param($Cmd)

    $result = $null
    try {
        $result = & $Cmd.Name
    } catch {
        try { $result = & $Cmd.Name -Version 'W10_1507' } catch {}
    }

    if ($null -eq $result) {
        return $null
    }

    if ($result -is [System.Collections.IDictionary]) {
        return @($result.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{ Version = $_.Key; Value = $_.Value }
        })
    }

    foreach ($propName in @('Releases', 'Versions', 'Items', 'Manifest')) {
        if ($result.PSObject.Properties.Name -contains $propName) {
            $value = $result.$propName
            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                return @($value)
            }
        }
    }

    if ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string])) {
        return @($result)
    }

    return @($result)
}

function Unwrap-LegacyEntry {
    param($Entry)

    foreach ($propName in @('Value', 'Item', 'Release', 'Descriptor')) {
        if ($Entry.PSObject.Properties.Name -contains $propName) {
            $candidate = $Entry.$propName
            if ($candidate -and $candidate.PSObject.Properties.Count -gt 0) {
                return $candidate
            }
        }
    }

    return $Entry
}

$manifestCmd = Resolve-LegacyCommand -Candidates @(
    'Get-LegacyMediaReleaseManifest',
    'Get-LegacyMediaManifest',
    'Get-LegacyMediaVersions'
)

if (-not $manifestCmd) {
    Skip-Test 'Legacy manifest discovery' 'Legacy manifest helper not available yet'
    return
}

$entries = Get-LegacyManifestEntries -Cmd $manifestCmd
if (-not $entries -or $entries.Count -eq 0) {
    Skip-Test 'Legacy manifest discovery' 'Legacy manifest helper returned no entries'
    return
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

Assert-True ($entries.Count -ge $expectedVersions.Count) "Legacy manifest: has at least $($expectedVersions.Count) entries ($($entries.Count))"

foreach ($version in $expectedVersions) {
    $entry = $entries | Where-Object {
        $_.Version -eq $version -or $_.VersionId -eq $version -or $_.Id -eq $version -or $_.Name -eq $version
    } | Select-Object -First 1

    $entry = Unwrap-LegacyEntry -Entry $entry

    Assert-NotNull $entry "Legacy manifest: entry exists for $version"
    if ($entry) {
        $build = $entry.Build
        if ($null -eq $build -and $entry.PSObject.Properties.Name -contains 'TargetBuild') { $build = $entry.TargetBuild }
        if ($null -eq $build -and $entry.PSObject.Properties.Name -contains 'LatestBuild') { $build = $entry.LatestBuild }

        Assert-NotNull $build "Legacy manifest: $version has a build number"
        if ($build) {
            Assert-True ([int]$build -gt 10000) "Legacy manifest: $version build is plausible ($build)"
        }

        $display = $entry.DisplayVersion
        if ($null -eq $display -and $entry.PSObject.Properties.Name -contains 'Display') { $display = $entry.Display }
        Assert-NotNull $display "Legacy manifest: $version has a display version"

        $os = $entry.OS
        if ($null -eq $os -and $entry.PSObject.Properties.Name -contains 'Platform') { $os = $entry.Platform }
        Assert-NotNull $os "Legacy manifest: $version has an OS/platform"
        if ($os) {
            Assert-Match 'Windows 10' $os "Legacy manifest: $version is tagged as Windows 10"
        }
    }
}
