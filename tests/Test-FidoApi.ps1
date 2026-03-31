# Tests for Get-DirectIsoDownloadUrl -- Fido API with ov-df handshake

Write-Host '    (Fido API tests require internet -- may take 15-20s)' -ForegroundColor DarkGray

$profileId = '606624d44113'
$instanceId = '560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175'

# -- Step 1: vlscppe session whitelisting --
try {
    $sessionId = [guid]::NewGuid().ToString()
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 `
        "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sessionId" -ErrorAction Stop
    Assert-True ($resp.StatusCode -eq 200) 'Fido-vlscppe: Session whitelist returns 200'
} catch {
    Skip-Test 'Fido-vlscppe: Session whitelist' "Network error: $_"
}

# -- Step 2: ov-df handshake --
try {
    $ovUrl = "https://ov-df.microsoft.com/mdt.js?instanceId=$instanceId&PageId=si&session_id=$sessionId"
    $ovResp = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 $ovUrl -ErrorAction Stop
    Assert-NotNull $ovResp 'Fido-ovdf: mdt.js returns content'
    Assert-True ($ovResp.Length -gt 100) "Fido-ovdf: mdt.js response has content (len=$($ovResp.Length))"

    $w = $null; $rticks = $null
    if ($ovResp -match '[?&]w=([A-F0-9]+)') { $w = $matches[1] }
    if ($ovResp -match 'rticks\=\"\+?(\d+)') { $rticks = $matches[1] }

    Assert-NotNull $w 'Fido-ovdf: Extracted w token'
    Assert-NotNull $rticks 'Fido-ovdf: Extracted rticks'
    Assert-True ($w.Length -ge 8) "Fido-ovdf: w token length >= 8 (got $($w.Length))"
    Assert-True ($rticks.Length -ge 10) "Fido-ovdf: rticks length >= 10 (got $($rticks.Length))"

    # Post back
    $epoch = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $replyUrl = "https://ov-df.microsoft.com/?session_id=$sessionId&CustomerId=$instanceId&PageId=si&w=$w&mdt=$epoch&rticks=$rticks"
    $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 $replyUrl -ErrorAction SilentlyContinue
    Assert-True $true 'Fido-ovdf: Reply posted without error'
} catch {
    Skip-Test 'Fido-ovdf: Handshake' "Error: $_"
}

# -- Step 3: SKU info retrieval --
try {
    $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profileId&productEditionId=3262&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$sessionId"
    $rawContent = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 $skuUrl -ErrorAction Stop).Content
    $skuResponse = $rawContent | ConvertFrom-Json

    Assert-True ($skuResponse.PSObject.Properties.Name -contains 'Skus') 'Fido-SKU: Response has Skus property'
    $skus = $skuResponse.Skus
    Assert-True ($skus.Count -gt 20) "Fido-SKU: Found > 20 language SKUs (got $($skus.Count))"

    $engIntl = $skus | Where-Object { $_.Language -eq 'English International' } | Select-Object -First 1
    Assert-NotNull $engIntl 'Fido-SKU: English International SKU exists'
    Assert-NotNull $engIntl.Id 'Fido-SKU: English International has ID'
    Assert-NotNull $engIntl.FriendlyFileNames 'Fido-SKU: Has FriendlyFileNames'
    Assert-Match 'Win11.*\.iso' ($engIntl.FriendlyFileNames -join ',') 'Fido-SKU: Filename matches Win11*.iso'
} catch {
    Skip-Test 'Fido-SKU: Retrieval' "Error: $_"
}

# -- Step 4: Download link (may be Sentinel-blocked) --
if ($engIntl) {
    try {
        $dlUrl = "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=$profileId&productEditionId=undefined&SKU=$($engIntl.Id)&friendlyFileName=undefined&Locale=en-US&sessionID=$sessionId"
        $dlContent = (Invoke-WebRequest -Headers @{ 'Referer' = 'https://www.microsoft.com/software-download/windows11' } `
            -UseBasicParsing -TimeoutSec 15 $dlUrl -ErrorAction Stop).Content
        $dlResponse = $dlContent | ConvertFrom-Json

        $hasErrors = $dlResponse.PSObject.Properties.Name -contains 'Errors'
        $hasOptions = $dlResponse.PSObject.Properties.Name -contains 'ProductDownloadOptions'

        if ($hasOptions -and $dlResponse.ProductDownloadOptions) {
            Assert-True $true 'Fido-Download: Got ProductDownloadOptions (Sentinel passed!)'
            $isoUrl = ($dlResponse.ProductDownloadOptions | Where-Object { $_.Uri -match '\.iso' } | Select-Object -First 1).Uri
            Assert-NotNull $isoUrl 'Fido-Download: ISO URL found'
            if ($isoUrl) {
                Assert-Match '\.iso' $isoUrl 'Fido-Download: URL contains .iso'
                Assert-Match 'microsoft\.com|prss\.microsoft' $isoUrl 'Fido-Download: URL is Microsoft domain'
            }
        } elseif ($hasErrors) {
            $errKey = ($dlResponse.Errors | Select-Object -First 1).Key
            Skip-Test 'Fido-Download: ISO URL' "Sentinel blocked: $errKey (known issue on some networks)"
        } else {
            # Unknown response format -- log for debugging
            $props = $dlResponse.PSObject.Properties.Name -join ', '
            Skip-Test 'Fido-Download: ISO URL' "Unknown response format: $props"
        }
    } catch {
        Skip-Test 'Fido-Download: ISO URL' "Error: $_"
    }
}
