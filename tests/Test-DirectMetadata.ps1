# Tests for the direct WU/direct release feature update client

Write-Host '    (Direct WU tests require internet -- may take 20-30s)' -ForegroundColor DarkGray

# -- release discovery returns usable metadata for recent versions --
$wuVersions = @(
    @{ Version = '25H2'; ExpectMatch = '25H2|26200' },
    @{ Version = '24H2'; ExpectMatch = '24H2|26100' }
)

foreach ($uv in $wuVersions) {
    try {
        $release = Get-WindowsFeatureReleaseInfo -TargetVersion $uv.Version -Arch 'amd64'

        Assert-NotNull $release "WU-release[$($uv.Version)]: Returns metadata"
        if ($release) {
            Assert-NotNull $release.UpdateId "WU-release[$($uv.Version)]: Has update GUID"
            Assert-NotNull $release.Name "WU-release[$($uv.Version)]: Has title"
            Assert-Equal 'WU Direct' $release.Source "WU-release[$($uv.Version)]: Source is direct WU"
            Assert-True ($release.Build -gt 10000) "WU-release[$($uv.Version)]: Target build is set"
            Assert-True ($release.LatestBuild -gt 10000) "WU-release[$($uv.Version)]: Latest build is set"
            $titlePattern = "$($uv.ExpectMatch)|Windows|Feature update|OOBE|Update"
            Assert-Match $titlePattern $release.Name "WU-release[$($uv.Version)]: Title looks correct"
        }
    }
    catch {
        Skip-Test "WU-release[$($uv.Version)]" "Direct WU metadata error: $_"
    }
}

# -- file retrieval returns direct CDN URLs and ESD payloads --
try {
    $filesResult = Get-WindowsFeatureFiles -TargetVersion '25H2' -Arch 'amd64' -Language 'en-us' -Edition 'professional'

    if (-not $filesResult) {
        Skip-Test 'WU-files: Returns metadata' 'Direct WU file metadata was not returned'
    }
    else {
        Assert-NotNull $filesResult 'WU-files: Returns metadata'
        $allEsds = @($filesResult.AllEsds)
        if ($allEsds.Count -eq 0) {
            if ($env:WFU_TOOL_CI_MODE -eq '1') {
                Skip-Test 'WU-files: Returns ESD list' 'Direct WU metadata exposed no ESD entries in CI mode'
            }
            else {
                Assert-True $false 'WU-files: Returns ESD list'
            }
        }
        else {
            Assert-True ($allEsds.Count -gt 0) "WU-files: Found ESD files (count: $($allEsds.Count))"
            Assert-NotNull $filesResult.Url 'WU-files: Selected ESD has download URL'
            Assert-True ([long]$filesResult.Size -gt 100MB) "WU-files: ESD size > 100 MB ($([math]::Round([long]$filesResult.Size / 1MB)) MB)"
            Assert-Match 'tlu\.dl\.delivery\.mp\.microsoft\.com|dl\.delivery\.mp\.microsoft\.com' $filesResult.Url 'WU-files: URL is Microsoft CDN'

            if ($filesResult.Sha1) {
                Assert-Match '^[0-9a-f]{40}$' $filesResult.Sha1 'WU-files: SHA1 is 40 hex chars'
            }
            else {
                Skip-Test 'WU-files: SHA1 digest' 'Metadata did not expose a convertible SHA1 digest'
            }

            try {
                $head = Invoke-WebRequest -Uri $filesResult.Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                Assert-True ($head.StatusCode -eq 200) 'WU-files: CDN URL is reachable (HTTP 200)'
                $cdnSize = [long]$head.Headers['Content-Length']
                Assert-True ($cdnSize -gt 100MB) "WU-files: CDN reports size > 100 MB ($([math]::Round($cdnSize / 1MB)) MB)"
            }
            catch {
                Skip-Test 'WU-files: CDN reachability' "HEAD request failed: $_"
            }
        }
    }
}
catch {
    Skip-Test 'WU-files: File retrieval' "Direct WU metadata error: $_"
}

# -- Build map correctness: previous build maps to next version --
$buildMap = @(
    @{ Version = '25H2'; FromBuild = '10.0.26100.1'; TargetBuild = 26200 },
    @{ Version = '24H2'; FromBuild = '10.0.22631.1'; TargetBuild = 26100 },
    @{ Version = '23H2'; FromBuild = '10.0.22621.1'; TargetBuild = 22631 },
    @{ Version = '22H2'; FromBuild = '10.0.22000.1'; TargetBuild = 22621 }
)

foreach ($entry in $buildMap) {
    $spec = Get-WindowsFeatureTargetSpec -TargetVersion $entry.Version
    Assert-NotNull $spec "WU-buildmap[$($entry.Version)]: Spec exists"
    if ($spec) {
        Assert-Equal $entry.FromBuild $spec.FromBuild "WU-buildmap[$($entry.Version)]: FROM build matches"
        Assert-Equal $entry.TargetBuild $spec.TargetBuild "WU-buildmap[$($entry.Version)]: Target build matches"
    }
}
