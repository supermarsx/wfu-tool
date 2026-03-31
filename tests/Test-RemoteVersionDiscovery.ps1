# Tests for Get-RemoteAvailableVersions (direct WU + Fido dual-source)

Write-Host '    (Remote version tests require internet -- may take 20-30s)' -ForegroundColor DarkGray

$versions = Get-RemoteAvailableVersions
$versions = @($versions)

if ($versions.Count -gt 0) {
    Assert-True ($versions.Count -ge 2) "RemoteVer: Found at least 2 versions ($($versions.Count))"

    # Check structure
    $first = $versions[0]
    Assert-NotNull $first.Version 'RemoteVer: First has Version key'
    Assert-NotNull $first.Build 'RemoteVer: First has Build number'
    Assert-NotNull $first.OS 'RemoteVer: First has OS name'
    Assert-NotNull $first.Source 'RemoteVer: First has Source (WU Direct/Fido)'
    Assert-True ($first.Available -eq $true) 'RemoteVer: First is marked Available'

    # Should find recent versions
    $versionKeys = $versions | ForEach-Object { $_.Version }
    $has25H2 = '25H2' -in $versionKeys
    $has24H2 = '24H2' -in $versionKeys
    Assert-True ($has25H2 -or $has24H2) 'RemoteVer: Found 25H2 or 24H2'

    # Source should be identified
    $sources = ($versions | ForEach-Object { $_.Source } | Sort-Object -Unique) -join ', '
    Assert-NotNull $sources "RemoteVer: Sources identified ($sources)"

    # All builds should be positive
    foreach ($v in $versions) {
        Assert-True ($v.Build -gt 10000) "RemoteVer: $($v.Version) build $($v.Build) > 10000"
    }

    # Check for Win10 if it was found
    $hasWin10 = $versionKeys | Where-Object { $_ -like 'W10_*' }
    if ($hasWin10) {
        $legacySupported = @(
            'W10_1507', 'W10_1511', 'W10_1607', 'W10_1703', 'W10_1709',
            'W10_1803', 'W10_1809', 'W10_1903', 'W10_1909', 'W10_2004',
            'W10_20H2', 'W10_21H1', 'W10_21H2', 'W10_22H2'
        )
        $legacyUnknown = @($hasWin10 | Where-Object { $_ -notin $legacySupported })
        Assert-True ($legacyUnknown.Count -eq 0) 'RemoteVer: Win10 versions use supported legacy labels'

        foreach ($legacyVersion in $hasWin10) {
            $legacyItem = $versions | Where-Object { $_.Version -eq $legacyVersion } | Select-Object -First 1
            Assert-NotNull $legacyItem.Source "RemoteVer[$legacyVersion]: Has a source label"
            Assert-Equal 'Windows 10' $legacyItem.OS "RemoteVer[$legacyVersion]: OS is Windows 10"
            Assert-True ($legacyItem.Build -gt 10000) "RemoteVer[$legacyVersion]: Build $($legacyItem.Build) > 10000"
            if ($legacyItem.PSObject.Properties.Name -contains 'SourceFamily') {
                Assert-NotNull $legacyItem.SourceFamily "RemoteVer[$legacyVersion]: Has a source family"
            } else {
                Skip-Test "RemoteVer[$legacyVersion]: Source family" 'SourceFamily is not surfaced by the current discovery shape'
            }
            if ($legacyItem.PSObject.Properties.Name -contains 'DiscoverySource') {
                Assert-True ($legacyItem.DiscoverySource -match 'Pinned|Manifest|Legacy') "RemoteVer[$legacyVersion]: Uses pinned legacy discovery"
            } else {
                Skip-Test "RemoteVer[$legacyVersion]: Discovery source" 'DiscoverySource is not surfaced by the current discovery shape'
            }
        }
    }
} else {
    Skip-Test 'RemoteVer: Discovery' 'No internet or all APIs rate-limited'
}
