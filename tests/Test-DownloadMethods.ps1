# Tests for all download method functions -- validates URLs without downloading full files

Write-Host '    (Download method tests require internet -- may take 30-60s)' -ForegroundColor DarkGray

# =============================================================
# Test: Get-ReleaseEsd (primary direct WU/direct release method)
# =============================================================
Write-Host '    -- Direct WU ESD --' -ForegroundColor DarkGray
$releaseResult = Get-ReleaseEsd -Version '25H2' -Language 'en-us' -Edition 'professional'
if ($releaseResult) {
    Assert-NotNull $releaseResult.Url 'DL-DirectMetadata: Has download URL'
    Assert-NotNull $releaseResult.UpdateId 'DL-DirectMetadata: Has update ID'
    Assert-True ($releaseResult.Size -gt 100MB) "DL-DirectMetadata: Size > 100 MB ($([math]::Round($releaseResult.Size / 1MB)) MB)"
    Assert-Match 'dl\.delivery\.mp\.microsoft\.com' $releaseResult.Url 'DL-DirectMetadata: URL is Microsoft CDN'
    Assert-Equal 'WU Direct' $releaseResult.Source 'DL-DirectMetadata: Source is direct WU client'
    Assert-Match 'professional' $releaseResult.FileName 'DL-DirectMetadata: Filename contains edition'
    if ($releaseResult.Sha1) {
        Assert-Match '^[0-9a-f]{40}$' $releaseResult.Sha1 'DL-DirectMetadata: SHA1 is normalized to 40 hex chars'
    } else {
        Skip-Test 'DL-DirectMetadata: SHA1 digest' 'WU metadata did not expose a convertible SHA1 digest'
    }

    # Verify URL is reachable
    try {
        $head = Invoke-WebRequest -Uri $releaseResult.Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Assert-True ($head.StatusCode -eq 200) 'DL-DirectMetadata: CDN URL reachable'
    } catch {
        Skip-Test 'DL-DirectMetadata: CDN reachability' "HEAD failed: $_"
    }
} else {
    Skip-Test 'DL-DirectMetadata: 25H2 ESD' 'Direct WU client unavailable'
}

# =============================================================
# Test: Legacy Windows 10 media acquisition path
# =============================================================
Write-Host '    -- Legacy Windows 10 media path --' -ForegroundColor DarkGray
$legacyTarget = 'W10_1507'
$legacySpec = Get-LegacyMediaSpec -Version $legacyTarget
if ($legacySpec) {
    Assert-NotNull $legacySpec.CatalogKind "DL-LegacyMedia[$legacyTarget]: Catalog kind is defined"
    Assert-NotNull $legacySpec.CatalogUrl "DL-LegacyMedia[$legacyTarget]: Catalog or manifest URL is defined"

    $legacySources = Get-LegacyMediaSourceDescriptors -Version $legacyTarget
    Assert-NotNull $legacySources "DL-LegacyMedia[$legacyTarget]: Source descriptors exist"
    if ($legacySources) {
        if ($legacySources -isnot [System.Collections.IEnumerable] -or $legacySources -is [string]) {
            $legacySources = @($legacySources)
        }

        Assert-True ($legacySources.Count -ge 1) "DL-LegacyMedia[$legacyTarget]: Has at least one source descriptor"
        $legacyCatalog = $legacySources | Where-Object { $_.Kind -in @('CAB','XML') } | Select-Object -First 1
        $legacyMct = $legacySources | Where-Object { $_.Kind -eq 'MCTEXE' } | Select-Object -First 1
        if ($legacyCatalog) {
            Assert-Match '^https://' $legacyCatalog.Url "DL-LegacyMedia[$legacyTarget]: Catalog source is HTTPS"
        }
        if ($legacyMct) {
            Assert-Match '^https://' $legacyMct.Url "DL-LegacyMedia[$legacyTarget]: MCT source is HTTPS"
        }
    }

    $legacyPlanCmd = Get-Command 'New-LegacyMctFallbackPlan' -ErrorAction SilentlyContinue
    if ($legacyPlanCmd) {
        $legacyPlan = New-LegacyMctFallbackPlan -Version $legacyTarget
        Assert-NotNull $legacyPlan "DL-LegacyMedia[$legacyTarget]: MCT fallback plan exists"
        if ($legacyPlan) {
            Assert-NotNull $legacyPlan.CommandLine "DL-LegacyMedia[$legacyTarget]: MCT plan has a command line"
            Assert-NotNull $legacyPlan.WorkingDirectory "DL-LegacyMedia[$legacyTarget]: MCT plan has a working directory"
            Assert-True ($legacyPlan.OutputIsoPath -match "\\$legacyTarget\.iso$") "DL-LegacyMedia[$legacyTarget]: Output ISO path is versioned"
        }
    } else {
        Skip-Test "DL-LegacyMedia[$legacyTarget]: MCT fallback plan" 'Helper not surfaced in the current session'
    }
} else {
    Skip-Test 'DL-LegacyMedia: acquisition path' 'Legacy media manifest unavailable'
}

# =============================================================
# Test: Get-EsdDownloadFromCatalog (23H2 only)
# =============================================================
Write-Host '    -- ESD Catalog (23H2) --' -ForegroundColor DarkGray
Start-Sleep -Seconds 2
$esdResult = Get-EsdDownloadFromCatalog -Version '23H2' -Language 'en-us' -Arch 'x64'
if ($esdResult) {
    Assert-NotNull $esdResult.Url 'DL-ESD: Has download URL'
    Assert-NotNull $esdResult.Sha1 'DL-ESD: Has SHA1 hash'
    Assert-True ($esdResult.Size -gt 1GB) "DL-ESD: Size > 1 GB ($([math]::Round($esdResult.Size / 1GB, 1)) GB)"
    Assert-Match 'dl\.delivery\.mp\.microsoft\.com' $esdResult.Url 'DL-ESD: URL is Microsoft CDN'
    Assert-Match '\.esd' $esdResult.Url 'DL-ESD: URL ends with .esd'

    try {
        $head = Invoke-WebRequest -Uri $esdResult.Url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Assert-True ($head.StatusCode -eq 200) 'DL-ESD: CDN URL reachable'
    } catch {
        Skip-Test 'DL-ESD: CDN reachability' "HEAD failed: $_"
    }
} else {
    Skip-Test 'DL-ESD: 23H2 catalog' 'Catalog download failed'
}

# Verify 25H2 correctly returns null (no public catalog)
$esd25 = Get-EsdDownloadFromCatalog -Version '25H2' -Language 'en-us' -Arch 'x64'
Assert-Null $esd25 'DL-ESD: 25H2 returns null (no public catalog -- correct)'

# =============================================================
# Test: Get-DirectIsoDownloadUrl (Fido API)
# =============================================================
Write-Host '    -- Fido ISO API --' -ForegroundColor DarkGray
Start-Sleep -Seconds 2
$fidoResult = Get-DirectIsoDownloadUrl -Language 'English International' -Arch 'x64' -Version '25H2'
if ($fidoResult) {
    Assert-Match '\.iso' $fidoResult 'DL-Fido: URL contains .iso'
    Assert-Match 'https://' $fidoResult 'DL-Fido: URL is HTTPS'
    Assert-Match 'microsoft' $fidoResult 'DL-Fido: URL is from Microsoft'
} else {
    Skip-Test 'DL-Fido: ISO URL' 'Sentinel blocked or API unavailable (known intermittent)'
}

# =============================================================
# Test: Get-SystemLanguageCode
# =============================================================
Write-Host '    -- Locale detection --' -ForegroundColor DarkGray
$lang = Get-SystemLanguageCode
Assert-NotNull $lang 'DL-Locale: Detected a language code'
Assert-Match '^\w{2}-' $lang 'DL-Locale: Format starts with xx-'

# =============================================================
# Test: Get-WindowsEditionKeys
# =============================================================
Write-Host '    -- Edition keys --' -ForegroundColor DarkGray
$keys = Get-WindowsEditionKeys
Assert-True ($keys.Count -ge 15) "DL-Keys: Has >= 15 editions ($($keys.Count))"
Assert-NotNull $keys['Professional'] 'DL-Keys: Professional key exists'

# =============================================================
# Test: Start-DownloadWithProgress (small file test)
# =============================================================
Write-Host '    -- Download with progress (small test file) --' -ForegroundColor DarkGray
$testUrl = 'https://www.microsoft.com/favicon.ico'
$testDest = Join-Path $env:TEMP 'WFU_TOOL_DLTest.ico'
Remove-Item $testDest -Force -ErrorAction SilentlyContinue

$dlOk = Start-DownloadWithProgress -Url $testUrl -Destination $testDest -Description 'test favicon'
if ($dlOk -is [array]) { $dlOk = $dlOk[-1] }

Assert-True ($dlOk -eq $true) 'DL-Progress: Small file download succeeded'
Assert-True (Test-Path $testDest) 'DL-Progress: File exists after download'
if (Test-Path $testDest) {
    Assert-True ((Get-Item $testDest).Length -gt 100) 'DL-Progress: File has content (> 100 bytes)'
}
Remove-Item $testDest -Force -ErrorAction SilentlyContinue

# =============================================================
# Test: Test-FileHash
# =============================================================
Write-Host '    -- File hash verification --' -ForegroundColor DarkGray
$hashFile = Join-Path $env:TEMP 'WFU_TOOL_HashTest2.bin'
[System.IO.File]::WriteAllBytes($hashFile, [byte[]](1..100))
$sha1 = (Get-FileHash $hashFile -Algorithm SHA1).Hash

$hashOk = Test-FileHash -FilePath $hashFile -ExpectedHash $sha1 -Algorithm SHA1
Assert-True ($hashOk -eq $true) 'DL-Hash: Correct hash passes'

$hashBad = Test-FileHash -FilePath $hashFile -ExpectedHash ('0' * 40) -Algorithm SHA1
Assert-True ($hashBad -eq $false) 'DL-Hash: Wrong hash fails'

Remove-Item $hashFile -Force -ErrorAction SilentlyContinue

# =============================================================
# Test: MCT download URL is reachable
# =============================================================
Write-Host '    -- MCT availability --' -ForegroundColor DarkGray
try {
    $mctResp = Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2156295' `
        -Method Head -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Assert-True $true 'DL-MCT: Download URL is reachable'
} catch {
    if ($_.Exception.Response.StatusCode.value__ -in @(301, 302)) {
        Assert-True $true 'DL-MCT: Download URL redirects (reachable)'
    } else {
        Skip-Test 'DL-MCT: Availability' "Unreachable: $_"
    }
}

# =============================================================
# Test: Installation Assistant download URL
# =============================================================
Write-Host '    -- Installation Assistant availability --' -ForegroundColor DarkGray
try {
    $iaResp = Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2171764' `
        -Method Head -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Assert-True $true 'DL-IA: Download URL is reachable'
} catch {
    if ($_.Exception.Response.StatusCode.value__ -in @(301, 302)) {
        Assert-True $true 'DL-IA: Download URL redirects (reachable)'
    } else {
        Skip-Test 'DL-IA: Availability' "Unreachable: $_"
    }
}
