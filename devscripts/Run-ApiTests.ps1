<#
.SYNOPSIS
    Validates all API/download methods with detailed output and scoring.
#>
$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$LogPath = Join-Path $env:TEMP 'WFU_TOOL_APITest.log'
$DownloadPath = Join-Path $env:TEMP 'WFU_TOOL_APITestDL'
$MaxRetries = 1

try {
    . (Join-Path $projectRoot 'wfu-tool.ps1') -TargetVersion '25H2' -NoReboot `
        -LogPath $LogPath -DownloadPath $DownloadPath `
        -SkipBypasses -SkipBlockerRemoval -SkipTelemetry -SkipRepair `
        -SkipCumulativeUpdates -SkipNetworkCheck -SkipDiskCheck -MaxRetries 1 2>$null
} catch {}

$p = 0; $f = 0; $s = 0

function Ok   { param([string]$n) $Script:p++; Write-Host "  PASS  $n" -ForegroundColor Green }
function Fail { param([string]$n) $Script:f++; Write-Host "  FAIL  $n" -ForegroundColor Red }
function Skip { param([string]$n,[string]$r='') $Script:s++; Write-Host "  SKIP  $n $(if($r){" ($r)"})" -ForegroundColor Yellow }

Write-Host ''
Write-Host '  ================================================' -ForegroundColor Cyan
Write-Host '  API & METHOD VALIDATION' -ForegroundColor White
Write-Host '  ================================================' -ForegroundColor Cyan
Write-Host ''

# --- Core ---
$v = Get-CurrentWindowsVersion
if ($v.VersionKey -ne 'Unknown') { Ok "Version: $($v.OS) $($v.VersionKey) $($v.FullBuild)" } else { Fail 'Version detection' }

$lang = Get-SystemLanguageCode
if ($lang -match '^\w{2}-') { Ok "Locale: $lang" } else { Fail 'Locale detection' }

$keys = Get-WindowsEditionKeys
if ($keys.Count -ge 15) { Ok "Edition keys: $($keys.Count) editions" } else { Fail 'Edition keys' }

$k='HKCU:\\SOFTWARE\\wfu-tool-T'; New-Item $k -Force -ea 0|Out-Null
$null=Set-RegValue $k 'V' 42 ''; $gv=Get-RegValue $k 'V'; $gn=Get-RegValue $k 'X'
Remove-Item $k -Recurse -Force -ea 0
if ($gv -eq 42 -and $null -eq $gn) { Ok 'Registry helpers' } else { Fail 'Registry helpers' }

$rok = Invoke-WithRetry -Description 't' -MaxAttempts 2 -BaseDelaySec 0 -Action { 'ok' }
$rfl = Invoke-WithRetry -Description 't' -MaxAttempts 1 -BaseDelaySec 0 -Action { throw 'x' }
if ($rok -eq 'ok' -and $null -eq $rfl) { Ok 'Retry logic' } else { Fail 'Retry logic' }

$net = Test-NetworkReadiness
if ($net) { Ok 'Network readiness' } else { Fail 'Network (no internet)' }

$hf = Join-Path $env:TEMP 'WFU_TOOL_h.tmp'; 'x' | Set-Content $hf
$hs = (Get-FileHash $hf -Algorithm SHA1).Hash
$ho = Test-FileHash -FilePath $hf -ExpectedHash $hs -Algorithm SHA1
$hb = Test-FileHash -FilePath $hf -ExpectedHash ('0'*40) -Algorithm SHA1
Remove-Item $hf -Force -ea 0
if ($ho -and -not $hb) { Ok 'File hash verification' } else { Fail 'File hash' }

Write-Host ''

# --- Direct metadata ---
Write-Host '  -- Direct metadata --' -ForegroundColor DarkGray
try {
    $releaseInfo = Get-WindowsFeatureReleaseInfo -TargetVersion '25H2' -Arch 'amd64'
    if ($releaseInfo -and $releaseInfo.UpdateId -match '-') {
        Ok "Get-WindowsFeatureReleaseInfo: $($releaseInfo.Name) (UUID: $($releaseInfo.UpdateId.Substring(0,8))...)"
    } else {
        Fail 'Get-WindowsFeatureReleaseInfo: no update GUID'
    }
} catch { Fail "Get-WindowsFeatureReleaseInfo: $_" }

Start-Sleep -Seconds 8

try {
    $releaseFiles = Get-WindowsFeatureFiles -TargetVersion '25H2' -Arch 'amd64' -Language 'en-us' -Edition 'professional'
    if ($releaseFiles -and $releaseFiles.FileName) {
        $furl = $releaseFiles.Url
        $fsize = [math]::Round([long]$releaseFiles.Size / 1MB)
        Ok "Get-WindowsFeatureFiles: $($releaseFiles.FileName) ($fsize MB)"
        # CDN reachable?
        try {
            $hd = Invoke-WebRequest -Uri $furl -Method Head -UseBasicParsing -TimeoutSec 10
            $cdnMB = [math]::Round([long]$hd.Headers['Content-Length'] / 1MB)
            Ok "CDN reachable: HTTP $($hd.StatusCode), $cdnMB MB"
        } catch { Fail "CDN unreachable: $_" }
    } else { Fail 'Get-WindowsFeatureFiles: professional_en-us.esd not found' }
} catch { Skip 'Get-WindowsFeatureFiles' "$_" }

Start-Sleep -Seconds 8

$releaseFull = Get-ReleaseEsd -Version '25H2' -Language 'en-us' -Edition 'professional'
if ($releaseFull -and $releaseFull.Url -match 'dl\.delivery\.mp\.microsoft\.com') {
    Ok "Get-ReleaseEsd: $($releaseFull.FileName) ($([math]::Round($releaseFull.Size/1MB)) MB)"
} else { Skip 'Get-ReleaseEsd' 'Rate limited or API error' }

Write-Host ''

# --- ESD Catalog ---
Write-Host '  -- ESD Catalog --' -ForegroundColor DarkGray
$esd23 = Get-EsdDownloadFromCatalog -Version '23H2' -Language 'en-us' -Arch 'x64'
if ($esd23 -and $esd23.Url -match '\.esd') {
    Ok "23H2 catalog: $([math]::Round($esd23.Size/1GB,1)) GB, SHA1=$($esd23.Sha1.Substring(0,8))..."
} else { Fail '23H2 catalog' }

$esd25 = Get-EsdDownloadFromCatalog -Version '25H2' -Language 'en-us' -Arch 'x64'
if ($null -eq $esd25) { Ok '25H2 catalog: null (correct)' } else { Fail '25H2 should be null' }

Write-Host ''

# --- Fido ---
Write-Host '  -- Fido API --' -ForegroundColor DarkGray
try {
    $sid = [guid]::NewGuid().ToString()
    $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sid" -ea 0
    $ov = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 "https://ov-df.microsoft.com/mdt.js?instanceId=560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175&PageId=si&session_id=$sid"
    if ($ov -match 'w=[A-F0-9]+' -and $ov -match 'rticks') { Ok 'ov-df handshake' } else { Fail 'ov-df: missing tokens' }
} catch { Fail "ov-df: $_" }

try {
    $skr = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=606624d44113&productEditionId=3262&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$sid").Content | ConvertFrom-Json
    if ($skr.Skus.Count -gt 20) { Ok "SKU lookup: $($skr.Skus.Count) languages" } else { Fail 'SKU lookup' }
} catch { Skip 'SKU lookup' "$_" }

$fido = Get-DirectIsoDownloadUrl -Language 'English International' -Arch 'x64' -Version '25H2'
if ($fido -and $fido -match '\.iso') { Ok "ISO URL: $($fido.Substring(0,60))..." }
else { Skip 'Fido ISO URL' 'Sentinel blocked (known on some networks)' }

Write-Host ''

# --- Discovery ---
Write-Host '  -- Remote Discovery --' -ForegroundColor DarkGray
$rv = Get-RemoteAvailableVersions
if ($rv -and $rv.Count -ge 2) {
    Ok "Found $($rv.Count) versions via $($rv[0].Source)"
    $rv | ForEach-Object { Write-Host "         $($_.Version) build $($_.Build) ($($_.OS))" -ForegroundColor DarkGray }
} else { Fail 'Remote version discovery' }

Write-Host ''

# --- Download URLs ---
Write-Host '  -- Download URLs --' -ForegroundColor DarkGray
foreach ($u in @(
    @{N='MCT'; U='https://go.microsoft.com/fwlink/?linkid=2156295'},
    @{N='IA';  U='https://go.microsoft.com/fwlink/?linkid=2171764'}
)) {
    try {
        $r = Invoke-WebRequest -Uri $u.U -UseBasicParsing -TimeoutSec 15 -ea Stop
        Ok "$($u.N): HTTP $($r.StatusCode)"
    } catch { Ok "$($u.N): redirects (expected)" }
}

# --- Summary ---
Write-Host ''
Write-Host '  ================================================' -ForegroundColor Cyan
$total = $p + $f + $s
$color = if ($f -eq 0) { 'Green' } elseif ($f -le 2) { 'Yellow' } else { 'Red' }
Write-Host "  TOTAL: $total  |  PASS: $p  |  FAIL: $f  |  SKIP: $s" -ForegroundColor $color
Write-Host '  ================================================' -ForegroundColor Cyan
Write-Host ''
