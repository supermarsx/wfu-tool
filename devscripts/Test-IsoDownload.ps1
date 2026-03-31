<#
.SYNOPSIS
    Interactive test for the ISO download pipeline.
    Tests each download method independently:
    1. Fido API (ov-df handshake)
    2. ESD catalog
    3. MCT unattended
    Does NOT actually download the full ISO -- just validates the URLs.
#>
param([switch]$ActuallyDownload)

$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path $PSScriptRoot -Parent

# Source functions
$env:WFU_TOOL_TEST_MODE = '1'
. (Join-Path $projectRoot 'wfu-tool.ps1') -TargetVersion '25H2' -NoReboot `
    -LogPath (Join-Path $env:TEMP 'WFU_TOOL_IsoTest.log') `
    -DownloadPath (Join-Path $env:TEMP 'WFU_TOOL_IsoTestDL') `
    -SkipBypasses -SkipBlockerRemoval -SkipTelemetry -SkipRepair `
    -SkipCumulativeUpdates -SkipNetworkCheck -SkipDiskCheck -MaxRetries 1 2>$null

Write-Host ''
Write-Host '  ISO DOWNLOAD PIPELINE TEST' -ForegroundColor Cyan
Write-Host '  ==========================' -ForegroundColor Cyan
Write-Host ''

# Test 1: Locale detection
Write-Host '  [1] Locale Detection' -ForegroundColor Yellow
$lang = Get-SystemLanguageCode
Write-Host "      System language: $lang" -ForegroundColor $(if ($lang) { 'Green' } else { 'Red' })

# Test 2: Fido API with ov-df
Write-Host ''
Write-Host '  [2] Fido API (ov-df handshake) -- 25H2 English International' -ForegroundColor Yellow
$isoUrl = Get-DirectIsoDownloadUrl -Language 'English International' -Arch 'x64' -Version '25H2'
if ($isoUrl) {
    Write-Host "      URL: $($isoUrl.Substring(0, [math]::Min(100, $isoUrl.Length)))..." -ForegroundColor Green
    # Verify the URL is actually reachable
    try {
        $head = Invoke-WebRequest -Uri $isoUrl -Method Head -UseBasicParsing -TimeoutSec 10
        $sizeMB = [math]::Round([long]$head.Headers['Content-Length'] / 1MB)
        Write-Host "      Reachable: YES ($sizeMB MB)" -ForegroundColor Green
    }
    catch {
        Write-Host "      Reachable: NO ($_)" -ForegroundColor Red
    }
}
else {
    Write-Host '      FAILED (Sentinel may have blocked)' -ForegroundColor Red
}

# Test 3: ESD Catalog (23H2 only)
Write-Host ''
Write-Host '  [3] ESD Catalog -- 23H2 en-us' -ForegroundColor Yellow
$esdInfo = Get-EsdDownloadFromCatalog -Version '23H2' -Language 'en-us' -Arch 'x64'
if ($esdInfo) {
    Write-Host "      File: $($esdInfo.FileName)" -ForegroundColor Green
    Write-Host "      URL: $($esdInfo.Url.Substring(0, [math]::Min(100, $esdInfo.Url.Length)))..." -ForegroundColor Green
    Write-Host "      SHA1: $($esdInfo.Sha1)" -ForegroundColor Green
    Write-Host "      Size: $([math]::Round($esdInfo.Size / 1MB)) MB" -ForegroundColor Green
    # Verify URL
    try {
        $head = Invoke-WebRequest -Uri $esdInfo.Url -Method Head -UseBasicParsing -TimeoutSec 10
        Write-Host "      Reachable: YES" -ForegroundColor Green
    }
    catch {
        Write-Host "      Reachable: NO ($_)" -ForegroundColor Red
    }
}
else {
    Write-Host '      FAILED (catalog download or parse error)' -ForegroundColor Red
}

# Test 4: MCT availability
Write-Host ''
Write-Host '  [4] Media Creation Tool -- availability check' -ForegroundColor Yellow
$mctUrl = 'https://go.microsoft.com/fwlink/?linkid=2156295'
try {
    $head = Invoke-WebRequest -Uri $mctUrl -Method Head -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Write-Host "      MCT download URL: reachable (redirects to actual EXE)" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 301 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
        Write-Host "      MCT download URL: reachable (302 redirect)" -ForegroundColor Green
    }
    else {
        Write-Host "      MCT download URL: unreachable ($_)" -ForegroundColor Red
    }
}

# Test 5: Direct metadata discovery
Write-Host ''
Write-Host '  [5] Direct metadata discovery -- version lookup' -ForegroundColor Yellow
try {
    $release = Get-WindowsFeatureReleaseInfo -TargetVersion '25H2' -Arch 'amd64'
    if ($release) {
        Write-Host "      Latest 25H2: $($release.Name)" -ForegroundColor Green
        Write-Host "      Build: $($release.LatestBuild)" -ForegroundColor Green
    }
    else {
        Write-Host '      No release metadata found' -ForegroundColor Red
    }
}
catch {
    Write-Host "      Direct metadata discovery failed: $_" -ForegroundColor Red
}

Write-Host ''
Write-Host '  Done.' -ForegroundColor Cyan
Write-Host ''
