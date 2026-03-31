<#
.SYNOPSIS
    Standalone PowerShell implementation of the Windows Update SOAP API client.
    Provenance and third-party notices are documented in third-party-notices.md.

    Talks directly to Microsoft's WU SOAP endpoint at fe3.delivery.mp.microsoft.com
    to discover available updates, get file lists, and obtain direct CDN download URLs.
    No rate limiting, no Sentinel, no third-party API dependency.

.DESCRIPTION
    Functions:
    - Get-WuCookie        : Gets an encrypted session cookie from WU
    - Find-WuUpdate       : Searches for available updates (feature updates, CUs, etc.)
    - Get-WuFileUrls      : Gets direct download URLs for a specific update
    - Find-WindowsBuild   : High-level: finds the latest build for a given version

.NOTES
    PowerShell port for wfu-tool project.
#>

# =====================================================================
# Region: Helpers
# =====================================================================

function New-WuUuid {
    return [guid]::NewGuid().ToString()
}

function New-WuDeviceToken {
    <#
    .SYNOPSIS
        Generates a fake MSA device authentication token.
        Generates the encoded device token expected by the WU SOAP service.
    #>
    $header = '13003002c377040014d5bcac7a66de0d50beddf9bba16c87edb9e019898000'
    $random = -join ((0..1053) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $footer = 'b401'
    $hexStr = $header + $random + $footer

    # Convert hex to bytes
    $bytes = [byte[]]::new($hexStr.Length / 2)
    for ($i = 0; $i -lt $hexStr.Length; $i += 2) {
        $bytes[$i / 2] = [Convert]::ToByte($hexStr.Substring($i, 2), 16)
    }
    $tValue = [Convert]::ToBase64String($bytes)

    $data = "t=$tValue&p="
    # Encode as UTF-16LE with null bytes between chars (chunk_split equivalent)
    $utf16 = [System.Text.Encoding]::Unicode.GetBytes($data)
    return [Convert]::ToBase64String($utf16)
}

function Get-WuTimestamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-WuExpiry {
    param([int]$OffsetSeconds = 120)
    return (Get-Date).AddSeconds($OffsetSeconds).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-WuEpoch {
    return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

function ConvertTo-HtmlEntities {
    param([string]$Text)
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

# =====================================================================
# Region: Branch mapping
# =====================================================================

function Get-WuBranch {
    param([int]$Build)
    switch ($Build) {
        15063 { return 'rs2_release' }
        16299 { return 'rs3_release' }
        17134 { return 'rs4_release' }
        17763 { return 'rs5_release' }
        17784 { return 'rs5_release_svc_hci' }
        { $_ -in 18362,18363 } { return '19h1_release' }
        { $_ -in 19041,19042,19043,19044,19045,19046 } { return 'vb_release' }
        20279 { return 'fe_release_10x' }
        { $_ -in 20348,20349 } { return 'fe_release' }
        22000 { return 'co_release' }
        { $_ -in 22621,22631,22635 } { return 'ni_release' }
        25398 { return 'zn_release' }
        { $_ -in 26100,26120,26200 } { return 'ge_release' }
        28000 { return 'br_release' }
        default { return 'rs_prerelease' }
    }
}

# =====================================================================
# Region: Device Attributes
# =====================================================================

function New-WuDeviceAttributes {
    <#
    .SYNOPSIS
        Composes the DeviceAttributes string for WU SOAP requests.
    #>
    param(
        [string]$Ring = 'RETAIL',
        [string]$Build = '10.0.26100.1',
        [string]$Arch = 'amd64',
        [int]$Sku = 48,
        [string]$Branch = 'auto'
    )

    $buildNum = [int](($Build -split '\.')[2])
    if ($Branch -eq 'auto') { $Branch = Get-WuBranch -Build $buildNum }

    $epoch = Get-WuEpoch
    $dataExp = $epoch + 82800
    $tsExp = $epoch - 3600

    $flightEnabled = 0
    $isRetail = 1
    $fltRing = 'Retail'
    $fltBranch = ''

    $attribs = @(
        "App=WU_OS"
        "AppVer=$Build"
        "AttrDataVer=331"
        "AllowInPlaceUpgrade=1"
        "AllowOptionalContent=1"
        "AllowUpgradesWithUnsupportedTPMOrCPU=1"
        "BlockFeatureUpdates=0"
        "BranchReadinessLevel=CB"
        "CIOptin=1"
        "CurrentBranch=$Branch"
        "DataExpDateEpoch_GE25H2=$dataExp"
        "DataExpDateEpoch_GE24H2=$dataExp"
        "DataExpDateEpoch_GE24H2Setup=$dataExp"
        "DataExpDateEpoch_CU23H2=$dataExp"
        "DataExpDateEpoch_NI22H2=$dataExp"
        "DataExpDateEpoch_CO21H2=$dataExp"
        "DataVer_RS5=2000000000"
        "DefaultUserRegion=191"
        "DeviceFamily=Windows.Desktop"
        "DeviceInfoGatherSuccessful=1"
        "FlightRing=$fltRing"
        "Free=gt64"
        "GStatus_GE25H2=2"
        "GStatus_GE24H2=2"
        "GStatus_CU23H2=2"
        "GStatus_NI22H2=2"
        "GStatus_CO21H2=2"
        "GStatus_22H2=2"
        "GStatus_21H2=2"
        "GStatus_20H1=2"
        "GStatus_19H1=2"
        "GStatus_RS5=2"
        "InstallDate=1438196400"
        "InstallLanguage=en-US"
        "InstallationType=Client"
        "IsDeviceRetailDemo=0"
        "IsFlightingEnabled=$flightEnabled"
        "IsRetailOS=$isRetail"
        "MediaBranch="
        "MediaVersion=$Build"
        "OEMModel=SystemProductName"
        "OEMName_Uncleaned=System manufacturer"
        "OSArchitecture=$Arch"
        "OSSkuId=$Sku"
        "OSUILocale=en-US"
        "OSVersion=$Build"
        "ProcessorIdentifier=Intel64 Family 6 Model 186 Stepping 3"
        "ProcessorManufacturer=GenuineIntel"
        "ProductType=WinNT"
        "ReleaseType=Production"
        "SecureBootCapable=1"
        "TelemetryLevel=3"
        "TPMVersion=2"
        "UpdateManagementGroup=2"
        "UpgEx_GE25H2=Green"
        "UpgEx_GE24H2=Green"
        "UpgEx_CU23H2=Green"
        "UpgEx_NI22H2=Green"
        "UpgEx_CO21H2=Green"
        "UpgEx_22H2=Green"
        "UpgEx_21H2=Green"
        "UpgEx_20H1=Green"
        "UpgEx_19H1=Green"
        "UpgEx_RS5=Green"
        "UpgradeAccepted=1"
        "UpgradeEligible=1"
        "WuClientVer=$Build"
    )

    # HTML-encode once: & -> &amp; for XML embedding
    return [System.Net.WebUtility]::HtmlEncode("E:" + ($attribs -join '&'))
}

# =====================================================================
# Region: SOAP Request Composers
# =====================================================================

function New-WuGetCookieRequest {
    $device = New-WuDeviceToken
    $uuid = New-WuUuid
    $created = Get-WuTimestamp
    $expires = Get-WuExpiry

    return @"
<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:s="http://www.w3.org/2003/05/soap-envelope">
    <s:Header>
        <a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/GetCookie</a:Action>
        <a:MessageID>urn:uuid:$uuid</a:MessageID>
        <a:To s:mustUnderstand="1">https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx</a:To>
        <o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
                <Created>$created</Created>
                <Expires>$expires</Expires>
            </Timestamp>
            <wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization">
                <TicketType Name="MSA" Version="1.0" Policy="MBI_SSL">
                    <Device>$device</Device>
                </TicketType>
            </wuws:WindowsUpdateTicketsToken>
        </o:Security>
    </s:Header>
    <s:Body>
        <GetCookie xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService">
            <lastChange>2023-10-01</lastChange>
            <currentTime>$(Get-WuTimestamp)</currentTime>
            <protocolVersion>2.50</protocolVersion>
        </GetCookie>
    </s:Body>
</s:Envelope>
"@
}

function New-WuSyncUpdatesRequest {
    param(
        [string]$EncryptedCookie,
        [string]$Arch = 'amd64',
        [string]$Build = '10.0.26100.1',
        [string]$Ring = 'RETAIL',
        [int]$Sku = 48,
        [string]$Branch = 'auto'
    )

    $device = New-WuDeviceToken
    $uuid = New-WuUuid
    $created = Get-WuTimestamp
    $expires = Get-WuExpiry
    $cookieExpires = Get-WuExpiry -OffsetSeconds 604800

    $buildNum = [int](($Build -split '\.')[2])
    if ($Branch -eq 'auto') { $Branch = Get-WuBranch -Build $buildNum }

    $mainProduct = 'Client.OS.rs2'
    # Products use & as separator within each PN entry, ; between entries
    # Must be HTML-encoded ONCE (& -> &amp;) for the SOAP XML
    $rawProducts = @(
        "PN=$mainProduct.$Arch&Branch=$Branch&PrimaryOSProduct=1&Repairable=1&V=$Build&ReofferUpdate=1"
        "PN=Adobe.Flash.$Arch&Repairable=1&V=0.0.0.0"
        "PN=Microsoft.Edge.Stable.$Arch&Repairable=1&V=0.0.0.0"
        "PN=Microsoft.NETFX.$Arch&V=0.0.0.0"
        "PN=Windows.Appraiser.$Arch&Repairable=1&V=$Build"
        "PN=Windows.EmergencyUpdate.$Arch&V=$Build"
        "PN=Windows.FeatureExperiencePack.$Arch&Repairable=1&V=0.0.0.0"
        "PN=Windows.OOBE.$Arch&IsWindowsOOBE=1&Repairable=1&V=$Build"
        "PN=Windows.UpdateStackPackage.$Arch&Name=Update Stack Package&Repairable=1&V=$Build"
        "PN=Hammer.$Arch&Source=UpdateOrchestrator&V=0.0.0.0"
        "PN=MSRT.$Arch&Source=UpdateOrchestrator&V=0.0.0.0"
        "PN=SedimentPack.$Arch&Source=UpdateOrchestrator&V=0.0.0.0"
        "PN=UUS.$Arch&Source=UpdateOrchestrator&V=0.0.0.0"
    ) -join ';'
    $products = [System.Net.WebUtility]::HtmlEncode($rawProducts)
    $deviceAttribs = New-WuDeviceAttributes -Ring $Ring -Build $Build -Arch $Arch -Sku $Sku -Branch $Branch
    $callerAttribs = [System.Net.WebUtility]::HtmlEncode('E:Profile=AUv2&Acquisition=1&Interactive=1&IsSeeker=1&SheddingAware=1&Id=MoUpdateOrchestrator')

    # InstalledNonLeafUpdateIDs -- required magic numbers from the upstream source snapshot
    $installedIds = @(1,10,105939029,105995585,106017178,107825194,10809856,11,117765322,129905029,130040030,130040031,130040032,130040033,133399034,138372035,138372036,139536037,139536038,139536039,139536040,142045136,158941041,158941042,158941043,158941044,159776047,160733048,160733049,160733050,160733051,160733055,160733056,161870057,161870058,161870059,17,19,2,23110993,23110994,23110995,23110996,23110999,23111000,23111001,23111002,23111003,23111004,2359974,2359977,24513870,28880263,296374060,3,30077688,30486944,5143990,5169043,5169044,5169047,59830006,59830007,59830008,60484010,62450018,62450019,62450020,69801474,8788830,8806526,9125350,9154769,98959022,98959023,98959024,98959025,98959026)
    $idsXml = ($installedIds | ForEach-Object { "                    <int>$_</int>" }) -join "`n"

    return @"
<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:s="http://www.w3.org/2003/05/soap-envelope">
    <s:Header>
        <a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/SyncUpdates</a:Action>
        <a:MessageID>urn:uuid:$uuid</a:MessageID>
        <a:To s:mustUnderstand="1">https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx</a:To>
        <o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
                <Created>$created</Created>
                <Expires>$expires</Expires>
            </Timestamp>
            <wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization">
                <TicketType Name="MSA" Version="1.0" Policy="MBI_SSL">
                    <Device>$device</Device>
                </TicketType>
            </wuws:WindowsUpdateTicketsToken>
        </o:Security>
    </s:Header>
    <s:Body>
        <SyncUpdates xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService">
            <cookie>
                <Expiration>$cookieExpires</Expiration>
                <EncryptedData>$EncryptedCookie</EncryptedData>
            </cookie>
            <parameters>
                <ExpressQuery>false</ExpressQuery>
                <InstalledNonLeafUpdateIDs>
$idsXml
                </InstalledNonLeafUpdateIDs>
                <OtherCachedUpdateIDs/>
                <SkipSoftwareSync>false</SkipSoftwareSync>
                <NeedTwoGroupOutOfScopeUpdates>true</NeedTwoGroupOutOfScopeUpdates>
                <AlsoPerformRegularSync>true</AlsoPerformRegularSync>
                <ComputerSpec/>
                <ExtendedUpdateInfoParameters>
                    <XmlUpdateFragmentTypes>
                        <XmlUpdateFragmentType>Extended</XmlUpdateFragmentType>
                        <XmlUpdateFragmentType>LocalizedProperties</XmlUpdateFragmentType>
                    </XmlUpdateFragmentTypes>
                    <Locales>
                        <string>en-US</string>
                    </Locales>
                </ExtendedUpdateInfoParameters>
                <ClientPreferredLanguages/>
                <ProductsParameters>
                    <SyncCurrentVersionOnly>false</SyncCurrentVersionOnly>
                    <DeviceAttributes>$deviceAttribs</DeviceAttributes>
                    <CallerAttributes>$callerAttribs</CallerAttributes>
                    <Products>$products</Products>
                </ProductsParameters>
            </parameters>
        </SyncUpdates>
    </s:Body>
</s:Envelope>
"@
}

function New-WuFileGetRequest {
    param(
        [string]$UpdateId,
        [int]$RevisionNumber = 1
    )

    $device = New-WuDeviceToken
    $uuid = New-WuUuid
    $created = Get-WuTimestamp
    $expires = Get-WuExpiry
    $deviceAttribs = New-WuDeviceAttributes

    return @"
<s:Envelope xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:s="http://www.w3.org/2003/05/soap-envelope">
    <s:Header>
        <a:Action s:mustUnderstand="1">http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService/GetExtendedUpdateInfo2</a:Action>
        <a:MessageID>urn:uuid:$uuid</a:MessageID>
        <a:To s:mustUnderstand="1">https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured</a:To>
        <o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <Timestamp xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
                <Created>$created</Created>
                <Expires>$expires</Expires>
            </Timestamp>
            <wuws:WindowsUpdateTicketsToken wsu:id="ClientMSA" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wuws="http://schemas.microsoft.com/msus/2014/10/WindowsUpdateAuthorization">
                <TicketType Name="MSA" Version="1.0" Policy="MBI_SSL">
                    <Device>$device</Device>
                </TicketType>
            </wuws:WindowsUpdateTicketsToken>
        </o:Security>
    </s:Header>
    <s:Body>
        <GetExtendedUpdateInfo2 xmlns="http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService">
            <updateIDs>
                <UpdateIdentity>
                    <UpdateID>$UpdateId</UpdateID>
                    <RevisionNumber>$RevisionNumber</RevisionNumber>
                </UpdateIdentity>
            </updateIDs>
            <infoTypes>
                <XmlUpdateFragmentType>FileUrl</XmlUpdateFragmentType>
                <XmlUpdateFragmentType>FileDecryption</XmlUpdateFragmentType>
                <XmlUpdateFragmentType>PiecesHashUrl</XmlUpdateFragmentType>
                <XmlUpdateFragmentType>BlockMapUrl</XmlUpdateFragmentType>
            </infoTypes>
            <deviceAttributes>$deviceAttribs</deviceAttributes>
        </GetExtendedUpdateInfo2>
    </s:Body>
</s:Envelope>
"@
}

# =====================================================================
# Region: SOAP Transport
# =====================================================================

function Send-WuSoapRequest {
    <#
    .SYNOPSIS
        Sends a SOAP POST request to Microsoft's WU endpoint.
        User-Agent must match Windows Update Agent format.
    #>
    param(
        [string]$Url,
        [string]$Body,
        [int]$TimeoutSec = 30
    )

    try {
        $headers = @{
            'Content-Type' = 'application/soap+xml; charset=utf-8'
            'User-Agent'   = 'Windows-Update-Agent/10.0.10011.16384 Client-Protocol/2.50'
        }

        $response = Invoke-WebRequest -Uri $Url -Method Post -Body $Body `
            -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop

        return @{
            StatusCode = $response.StatusCode
            Content    = [System.Net.WebUtility]::HtmlDecode($response.Content)
        }
    } catch {
        return @{
            StatusCode = 0
            Content    = $null
            Error      = $_.Exception.Message
        }
    }
}

# =====================================================================
# Region: High-Level API Functions
# =====================================================================

function Get-WuCookie {
    <#
    .SYNOPSIS
        Gets an encrypted session cookie from the WU SOAP service.
        This cookie is required for SyncUpdates requests.
    #>
    $wuUrl = 'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx'
    $body = New-WuGetCookieRequest
    $response = Send-WuSoapRequest -Url $wuUrl -Body $body

    if ($response.StatusCode -ne 200 -or -not $response.Content) {
        Write-Warning "GetCookie failed: HTTP $($response.StatusCode)"
        return $null
    }

    $content = $response.Content
    if ($content -match '<EncryptedData>(.*?)</EncryptedData>') {
        return $matches[1]
    }

    Write-Warning 'Could not extract EncryptedData from cookie response.'
    return $null
}

function Find-WuUpdate {
    <#
    .SYNOPSIS
        Searches for available Windows updates by querying the WU SOAP API directly.
        Returns an array of update objects with UpdateID, Title, Build, etc.
    .PARAMETER Build
        The base build to search FROM (e.g. "10.0.26100.1" to find 25H2 upgrade)
    .PARAMETER Arch
        Architecture: amd64, x86, arm64
    .PARAMETER Ring
        Release ring: RETAIL, WIF (Dev), WIS (Beta), RP (Release Preview)
    #>
    param(
        [string]$Build = '10.0.26100.1',
        [string]$Arch = 'amd64',
        [string]$Ring = 'RETAIL',
        [int]$Sku = 48
    )

    # Step 1: Get cookie
    Write-Host "  WU API: Getting session cookie..." -ForegroundColor DarkGray
    $cookie = Get-WuCookie
    if (-not $cookie) {
        Write-Warning 'Failed to get WU cookie.'
        return @()
    }

    # Step 2: Sync updates
    Write-Host "  WU API: Querying for updates (build $Build, $Arch, $Ring)..." -ForegroundColor DarkGray
    $wuUrl = 'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx'
    $body = New-WuSyncUpdatesRequest -EncryptedCookie $cookie -Build $Build -Arch $Arch -Ring $Ring -Sku $Sku

    $response = Send-WuSoapRequest -Url $wuUrl -Body $body -TimeoutSec 60

    if ($response.StatusCode -ne 200 -or -not $response.Content) {
        Write-Warning "SyncUpdates failed: HTTP $($response.StatusCode) $($response.Error)"
        return @()
    }

    $content = $response.Content

    # Parse update entries from <NewUpdates><UpdateInfo>...</UpdateInfo></NewUpdates>
    $updates = @()
    $updateInfoMatches = [regex]::Matches($content, '<UpdateInfo>(.*?)</UpdateInfo>', [System.Text.RegularExpressions.RegexOptions]::Singleline)

    # First pass: collect all UpdateInfo blocks with their IDs and leaf status
    $allInfos = @{}
    foreach ($match in $updateInfoMatches) {
        $info = $match.Groups[1].Value
        $numId = if ($info -match '<ID>(\d+)</ID>') { $matches[1] } else { '' }
        $isLeaf = $info -match '<IsLeaf>true</IsLeaf>'

        # The UpdateID is inside the <Xml> block as an attribute
        $updateId = if ($info -match 'UpdateID="([^"]+)"') { $matches[1] } else { '' }
        $revNum = if ($info -match 'RevisionNumber="(\d+)"') { [int]$matches[1] } else { 1 }

        if ($numId) {
            $allInfos[$numId] = @{
                NumericID      = $numId
                UpdateID       = $updateId
                RevisionNumber = $revNum
                IsLeaf         = $isLeaf
                Raw            = $info
            }
        }
    }

    # Second pass: find Titles from <ExtendedUpdateInfo><Updates><Update> blocks
    # Titles are in separate XML fragments that reference updates by ID attribute
    $titleMatches = [regex]::Matches($content, '<Title>(.*?)</Title>')
    $allTitles = @()
    foreach ($tm in $titleMatches) {
        $allTitles += $tm.Groups[1].Value
    }

    # The response has UpdateIdentity elements that map UpdateIDs to the blocks
    $identityMatches = [regex]::Matches($content, 'UpdateID="([^"]+)"')
    $allUpdateIds = @()
    foreach ($im in $identityMatches) {
        $allUpdateIds += $im.Groups[1].Value
    }

    # Build final update list: leaf updates with their titles
    foreach ($entry in $allInfos.Values) {
        if (-not $entry.IsLeaf) { continue }

        $upd = @{
            UpdateID       = $entry.UpdateID
            RevisionNumber = $entry.RevisionNumber
            NumericID      = $entry.NumericID
        }

        # Find matching title -- titles correspond positionally to UpdateIdentity elements
        # Or search by the UpdateID appearing near a Title
        $idx = $allUpdateIds.IndexOf($entry.UpdateID)
        if ($idx -ge 0 -and $idx -lt $allTitles.Count) {
            $upd['Title'] = $allTitles[$idx]
        }

        # Also try to find the title by searching nearby XML
        if (-not $upd['Title']) {
            foreach ($t in $allTitles) {
                if ($t -match 'Windows (10|11)') {
                    $upd['Title'] = $t
                    break
                }
            }
        }

        # Extract build from raw XML
        if ($entry.Raw -match '(\d{5}\.\d+)') {
            $upd['FoundBuild'] = $matches[1]
        }

        $updates += $upd
    }

    # If no leaf updates found with titles, also include titled non-leaf entries
    # that look like feature updates
    if ($updates.Count -eq 0) {
        foreach ($t in $allTitles) {
            if ($t -match 'Windows (10|11).*version') {
                $updates += @{
                    Title    = $t
                    UpdateID = if ($allUpdateIds.Count -gt 0) { $allUpdateIds[0] } else { '' }
                }
            }
        }
    }

    Write-Host "  WU API: Found $($updates.Count) update(s)." -ForegroundColor DarkGray
    return $updates
}

function Get-WuFileUrls {
    <#
    .SYNOPSIS
        Gets direct download URLs (Microsoft CDN) for a specific update's files.
        Uses the GetExtendedUpdateInfo2 SOAP call to the /secured endpoint.
    .PARAMETER UpdateId
        The GUID of the update (from Find-WuUpdate results)
    .PARAMETER RevisionNumber
        Revision number (usually 1)
    #>
    param(
        [string]$UpdateId,
        [int]$RevisionNumber = 1
    )

    $wuUrl = 'https://fe3cr.delivery.mp.microsoft.com/ClientWebService/client.asmx/secured'
    $body = New-WuFileGetRequest -UpdateId $UpdateId -RevisionNumber $RevisionNumber

    Write-Host "  WU API: Getting file URLs for $UpdateId..." -ForegroundColor DarkGray
    $response = Send-WuSoapRequest -Url $wuUrl -Body $body -TimeoutSec 30

    if ($response.StatusCode -ne 200 -or -not $response.Content) {
        Write-Warning "GetExtendedUpdateInfo2 failed: HTTP $($response.StatusCode)"
        return @()
    }

    $content = $response.Content

    # Parse file URLs from FileLocation elements
    $files = @()
    $fileMatches = [regex]::Matches($content, '<FileLocation>.*?</FileLocation>', [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($fm in $fileMatches) {
        $fl = $fm.Value
        $url = if ($fl -match '<Url>(.*?)</Url>') { $matches[1] } else { '' }
        $digest = if ($fl -match '<FileDigest>(.*?)</FileDigest>') { $matches[1] } else { '' }
        $size = if ($fl -match '<Size>(\d+)</Size>') { [long]$matches[1] } else { 0 }
        $esrp = if ($fl -match '<EsrpDecryptionInformation>(.*?)</EsrpDecryptionInformation>') { $matches[1] } else { '' }

        if ($url) {
            # Extract filename from URL
            $fileName = if ($url -match '/([^/?]+)(?:\?|$)') {
                [System.Uri]::UnescapeDataString($matches[1])
            } else {
                'unknown'
            }

            $files += @{
                Url      = $url
                FileName = $fileName
                Digest   = $digest
                Size     = $size
            }
        }
    }

    Write-Host "  WU API: Got $($files.Count) file URL(s)." -ForegroundColor DarkGray
    return $files
}

function Convert-WuFileDigestToSha1 {
    <#
    .SYNOPSIS
        Converts the WU SOAP FileDigest payload to a lowercase hex SHA1 when possible.
    #>
    param([string]$Digest)

    if ([string]::IsNullOrWhiteSpace($Digest)) {
        return $null
    }

    if ($Digest -match '^[0-9a-fA-F]{40}$') {
        return $Digest.ToLower()
    }

    try {
        $bytes = [Convert]::FromBase64String($Digest)
        if ($bytes.Length -eq 20) {
            return ([System.BitConverter]::ToString($bytes).Replace('-', '')).ToLower()
        }
    } catch {
    }

    return $null
}

function Get-WindowsFeatureTargetSpec {
    <#
    .SYNOPSIS
        Returns version metadata used by the direct WU/direct release client.
    #>
    param([string]$TargetVersion)

    $specs = @{
        '25H2'     = @{ Version = '25H2';     FromBuild = '10.0.26100.1'; TargetBuild = 26200; OS = 'Windows 11' }
        '24H2'     = @{ Version = '24H2';     FromBuild = '10.0.22631.1'; TargetBuild = 26100; OS = 'Windows 11' }
        '23H2'     = @{ Version = '23H2';     FromBuild = '10.0.22621.1'; TargetBuild = 22631; OS = 'Windows 11' }
        '22H2'     = @{ Version = '22H2';     FromBuild = '10.0.22000.1'; TargetBuild = 22621; OS = 'Windows 11' }
        '21H2'     = @{ Version = '21H2';     FromBuild = '10.0.19045.1'; TargetBuild = 22000; OS = 'Windows 11' }
        'W10_22H2' = @{ Version = 'W10_22H2'; FromBuild = '10.0.19044.1'; TargetBuild = 19045; OS = 'Windows 10' }
        'W10_21H2' = @{ Version = 'W10_21H2'; FromBuild = '10.0.19043.1'; TargetBuild = 19044; OS = 'Windows 10' }
    }

    return $specs[$TargetVersion]
}

function Select-WindowsFeatureUpdate {
    <#
    .SYNOPSIS
        Picks the most relevant feature update from a WU query result set.
    #>
    param(
        [array]$Updates,
        [string]$TargetVersion
    )

    if (-not $Updates -or $Updates.Count -eq 0) {
        return $null
    }

    $spec = Get-WindowsFeatureTargetSpec -TargetVersion $TargetVersion
    $targetBuild = if ($spec) { [int]$spec.TargetBuild } else { 0 }
    $targetMajor = if ($TargetVersion -match '(\d{2}H2|\d{2}H1|\d{4})') { $matches[1] } else { $TargetVersion }

    $scored = foreach ($upd in $Updates) {
        $title = [string]$upd.Title
        $score = 0

        if ($title -match [regex]::Escape($TargetVersion)) { $score += 100 }
        if ($targetMajor -and $title -match [regex]::Escape($targetMajor)) { $score += 60 }
        if ($title -match 'Feature update') { $score += 25 }
        if ($title -match 'Windows 11|Windows 10') { $score += 10 }

        $foundBuild = 0
        if ($upd.FoundBuild -match '^(\d+)') {
            $foundBuild = [int]$matches[1]
            if ($targetBuild -gt 0 -and $foundBuild -eq $targetBuild) { $score += 40 }
            if ($targetBuild -gt 0 -and $foundBuild -ge ($targetBuild - 5)) { $score += 20 }
        }

        [pscustomobject]@{
            Score      = $score
            FoundBuild = $foundBuild
            Update     = $upd
        }
    }

    return ($scored |
        Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'FoundBuild'; Descending = $true } |
        Select-Object -First 1).Update
}

function Get-WindowsFeatureReleaseInfo {
    <#
    .SYNOPSIS
        Returns the best direct WU/direct release metadata for a target feature release.
    #>
    param(
        [string]$TargetVersion = '25H2',
        [string]$Arch = 'amd64'
    )

    $spec = Get-WindowsFeatureTargetSpec -TargetVersion $TargetVersion
    if (-not $spec) {
        Write-Warning "Unknown target version: $TargetVersion"
        return $null
    }

    $updates = Find-WuUpdate -Build $spec.FromBuild -Arch $Arch -Ring 'RETAIL'
    $bestUpdate = Select-WindowsFeatureUpdate -Updates $updates -TargetVersion $TargetVersion
    if (-not $bestUpdate) {
        return $null
    }

    $latestBuild = $spec.TargetBuild
    if ($bestUpdate.FoundBuild -match '^(\d+)') {
        $latestBuild = [int]$matches[1]
    }

    return @{
        Version        = $spec.Version
        Build          = $spec.TargetBuild
        LatestBuild    = $latestBuild
        OS             = $spec.OS
        Name           = $bestUpdate.Title
        UpdateId       = $bestUpdate.UpdateID
        RevisionNumber = if ($bestUpdate.RevisionNumber) { [int]$bestUpdate.RevisionNumber } else { 1 }
        Source         = 'WU Direct'
        Available      = $true
    }
}

function Get-WindowsFeatureFiles {
    <#
    .SYNOPSIS
        Returns direct Microsoft CDN files for the target feature release.
    #>
    param(
        [string]$TargetVersion = '25H2',
        [string]$Arch = 'amd64',
        [string]$Language = 'en-us',
        [string]$Edition = 'professional'
    )

    $release = Get-WindowsFeatureReleaseInfo -TargetVersion $TargetVersion -Arch $Arch
    if (-not $release) {
        return $null
    }

    $files = Get-WuFileUrls -UpdateId $release.UpdateId -RevisionNumber $release.RevisionNumber
    if (-not $files -or $files.Count -eq 0) {
        return $null
    }

    $language = $Language.ToLower()
    $edition = $Edition.ToLower()
    $esdFiles = @(
        $files |
        Where-Object { $_.FileName -match '\.esd(?:$|\?)' } |
        ForEach-Object {
            @{
                Name = [string]$_.FileName
                Url  = [string]$_.Url
                Sha1 = Convert-WuFileDigestToSha1 -Digest ([string]$_.Digest)
                Size = [long]$_.Size
            }
        }
    )

    if ($esdFiles.Count -eq 0) {
        return $null
    }

    $editionEsd = $esdFiles | Where-Object { $_.Name.ToLower() -eq "${edition}_${language}.esd" } | Select-Object -First 1
    if (-not $editionEsd) {
        $editionEsd = $esdFiles | Where-Object { $_.Name.ToLower() -match [regex]::Escape($edition) } | Select-Object -First 1
    }
    if (-not $editionEsd) {
        $editionEsd = $esdFiles | Where-Object { $_.Name.ToLower() -match [regex]::Escape($language) } | Select-Object -First 1
    }
    if (-not $editionEsd) {
        $editionEsd = $esdFiles | Select-Object -First 1
    }

    return @{
        Url            = $editionEsd.Url
        Sha1           = $editionEsd.Sha1
        Sha256         = $null
        Size           = [long]$editionEsd.Size
        FileName       = $editionEsd.Name
        Build          = $release.LatestBuild
        Version        = $release.Version
        UpdateId       = $release.UpdateId
        RevisionNumber = $release.RevisionNumber
        Title          = $release.Name
        AllEsds        = $esdFiles
        Source         = 'WU Direct'
    }
}

function Find-WindowsBuild {
    <#
    .SYNOPSIS
        High-level function: finds the latest available Windows build for a given version.
        Combines Get-WuCookie + Find-WuUpdate + Get-WuFileUrls into one call.
    .PARAMETER TargetVersion
        Target version like '25H2', '24H2', '23H2', 'W10_22H2'
    .PARAMETER Arch
        Architecture (default: amd64)
    .EXAMPLE
        $result = Find-WindowsBuild -TargetVersion '25H2'
        $result.Updates  # Available updates
        $result.Files    # Download URLs (if an update was found)
    #>
    param(
        [string]$TargetVersion = '25H2',
        [string]$Arch = 'amd64'
    )

    $spec = Get-WindowsFeatureTargetSpec -TargetVersion $TargetVersion
    if (-not $spec) {
        Write-Warning "Unknown target version: $TargetVersion"
        return $null
    }

    Write-Host ''
    Write-Host "  === Windows Update Direct API ===" -ForegroundColor Cyan
    Write-Host "  Target: $TargetVersion (querying from build $($spec.FromBuild))" -ForegroundColor White
    Write-Host ''

    $updates = Find-WuUpdate -Build $spec.FromBuild -Arch $Arch -Ring 'RETAIL'

    if ($updates.Count -eq 0) {
        Write-Host '  No updates found.' -ForegroundColor Yellow
        return @{ Updates = @(); Files = @() }
    }

    # Show found updates
    Write-Host ''
    foreach ($upd in $updates) {
        $buildStr = if ($upd.FoundBuild) { " (build $($upd.FoundBuild))" } else { '' }
        Write-Host "  Update: $($upd.Title)$buildStr" -ForegroundColor Green
    }

    # Get file URLs for the first/best update
    $bestUpdate = Select-WindowsFeatureUpdate -Updates $updates -TargetVersion $TargetVersion
    if ($bestUpdate) {
        Write-Host ''
        $files = Get-WuFileUrls -UpdateId $bestUpdate.UpdateID -RevisionNumber $bestUpdate.RevisionNumber

        # Filter to ESD files
        $esdFiles = $files | Where-Object { $_.FileName -match '\.esd$' }
        if ($esdFiles.Count -gt 0) {
            Write-Host "  ESD files: $($esdFiles.Count)" -ForegroundColor Green
            foreach ($f in $esdFiles) {
                $sizeMB = [math]::Round($f.Size / 1MB)
                Write-Host "    $($f.FileName) ($sizeMB MB)" -ForegroundColor DarkGray
                Write-Host "    $($f.Url.Substring(0, [math]::Min(100, $f.Url.Length)))..." -ForegroundColor DarkGray
            }
        }

        return @{
            Updates = $updates
            Files   = $files
        }
    }

    return @{ Updates = $updates; Files = @() }
}
