# Tests for Get-RemoteAvailableVersions and Get-DirectIsoDownloadUrl

# -- Remote version discovery --
Write-Host '    (This test requires internet -- may take 15-30s)' -ForegroundColor DarkGray
$versions = Get-RemoteAvailableVersions
$versions = @($versions)

if ($versions.Count -gt 0) {
    Assert-True ($versions.Count -ge 2) 'RemoteVersions: Found at least 2 versions'

    # Check structure of returned objects
    $first = $versions[0]
    Assert-NotNull $first.Version 'RemoteVersions: First result has Version'
    Assert-NotNull $first.Build 'RemoteVersions: First result has Build'
    Assert-NotNull $first.OS 'RemoteVersions: First result has OS'
    Assert-True ($first.Available -eq $true) 'RemoteVersions: First result is Available'

    # Should find Win11 25H2 or 24H2
    $has25H2 = $versions | Where-Object { $_.Version -eq '25H2' }
    $has24H2 = $versions | Where-Object { $_.Version -eq '24H2' }
    Assert-True ($has25H2 -or $has24H2) 'RemoteVersions: Found 25H2 or 24H2'

    # Source should be identified
    Assert-NotNull $first.Source 'RemoteVersions: Source is identified (WU Direct/Fido)'

    # Legacy Windows 10 entries, when present, should be labeled consistently
    $legacyVersions = $versions | Where-Object { $_.Version -like 'W10_*' }
    if ($legacyVersions) {
        foreach ($legacy in $legacyVersions) {
            Assert-NotNull $legacy.Source "RemoteVersions[$($legacy.Version)]: Source is identified"
            Assert-Equal 'Windows 10' $legacy.OS "RemoteVersions[$($legacy.Version)]: OS is Windows 10"
            Assert-True ($legacy.Build -gt 10000) "RemoteVersions[$($legacy.Version)]: Build $($legacy.Build) > 10000"
            if ($legacy.PSObject.Properties.Name -contains 'SourceFamily') {
                Assert-NotNull $legacy.SourceFamily "RemoteVersions[$($legacy.Version)]: SourceFamily is identified"
            } else {
                Skip-Test "RemoteVersions[$($legacy.Version)]: SourceFamily" 'SourceFamily is not surfaced by the current discovery shape'
            }
            if ($legacy.PSObject.Properties.Name -contains 'DiscoverySource') {
                Assert-True ($legacy.DiscoverySource -match 'Pinned|Manifest|Legacy') "RemoteVersions[$($legacy.Version)]: Discovery source is pinned legacy data"
            } else {
                Skip-Test "RemoteVersions[$($legacy.Version)]: DiscoverySource" 'DiscoverySource is not surfaced by the current discovery shape'
            }
        }
    }
} else {
    Skip-Test 'RemoteVersions: Discovery' 'No internet or direct metadata unavailable'
}

# -- Direct ISO URL (Fido with ov-df) --
Write-Host '    (Testing Fido ISO download API -- may take 10s)' -ForegroundColor DarkGray
$isoUrl = Get-DirectIsoDownloadUrl -Language 'English International' -Arch 'x64' -Version '25H2'

if ($isoUrl) {
    Assert-Match '\.iso' $isoUrl 'DirectIsoUrl: URL contains .iso'
    Assert-Match '^https://' $isoUrl 'DirectIsoUrl: URL is HTTPS'
    Assert-Match 'microsoft\.com|prss\.microsoft' $isoUrl 'DirectIsoUrl: URL is from Microsoft CDN'
    Write-Host "    (Got URL: $($isoUrl.Substring(0, [math]::Min(80, $isoUrl.Length)))...)" -ForegroundColor DarkGray
} else {
    Skip-Test 'DirectIsoUrl: URL retrieval' 'Sentinel blocked or network issue (known intermittent)'
}
