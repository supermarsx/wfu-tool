function Get-WindowsEditionKeys {
    <#
    .SYNOPSIS
        Returns a hashtable of generic (setup-only) product keys for Windows 11 editions.
        These are NOT activation keys -- they only tell setup.exe which edition to install.
    #>
    return @{
        'Cloud'                      = 'V3WVW-N2PV2-CGWC3-34QGF-VMJ2C'
        'CloudN'                     = 'NH9J3-68WK7-6FB93-4K3DF-DJ4F6'
        'Core'                       = 'YTMG3-N6DKC-DKB77-7M9GH-8HVX7'
        'CoreN'                      = '4CPRK-NM3K3-X6XXQ-RXX86-WXCHW'
        'CoreSingleLanguage'         = 'BT79Q-G7N6G-PGBYW-4YWX6-6F4BT'
        'CoreCountrySpecific'        = 'N2434-X9D7W-8PF6X-8DV9T-8TYMD'
        'Professional'               = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
        'ProfessionalN'              = '2B87N-8KFHP-DKV6R-Y2C8J-PKCKT'
        'ProfessionalEducation'      = '8PTT6-RNW4C-6V7J2-C2D3X-MHBPB'
        'ProfessionalEducationN'     = 'GJTYN-HDMQY-FRR76-HVGC7-QPF8P'
        'ProfessionalWorkstation'    = 'DXG7C-N36C4-C4HTG-X4T3X-2YV77'
        'ProfessionalWorkstationN'   = 'WYPNQ-8C467-V2W6J-TX4WX-WT2RQ'
        'Education'                  = 'YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY'
        'EducationN'                 = '84NGF-MHBT6-FXBX8-QWJK7-DRR8H'
        'Enterprise'                 = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'
        'EnterpriseN'                = 'DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4'
        'EnterpriseS'                = 'NK96Y-D9CD8-W44CQ-R8YTK-DYJWX'
        'EnterpriseSN'               = '2DBW3-N2PJG-MVHW3-G7TDK-9HKR4'
    }
}

function Get-LegacyWindows10MediaManifest {
    <#
    .SYNOPSIS
        Returns the shared legacy Windows 10 manifest in the local discovery shape.
    #>
    $manifest = Get-LegacyMediaManifest
    return @(
        $manifest | ForEach-Object {
            $sources = @(Get-LegacyMediaSourceDescriptors -Version $_.Version)
            $autoEligibleSources = @($sources | Where-Object { $_.AutoEligible })
            $preferredSource = if ($autoEligibleSources.Count -gt 0) { $autoEligibleSources[0] } elseif ($sources.Count -gt 0) { $sources[0] } else { $null }
            $supportsCatalog = [bool]$_.CatalogUrl
            $supportsMct = [bool]($_.PreferredMctUrl -or $_.MctUrl -or $_.MctUrl32)
            $supportsWu = $_.Version -in @('W10_21H2', 'W10_22H2')
            $supportsFido = $_.Version -in @('W10_20H2', 'W10_21H2', 'W10_22H2')
            $name = if ($_.PSObject.Properties.Name -contains 'Name' -and $_.Name) { $_.Name } else { "Windows 10 $($_.DisplayVersion) x64" }
            $health = if ($preferredSource) { $preferredSource.Health } else { 'unknown' }
            $healthReason = if ($preferredSource) { $preferredSource.HealthReason } else { '' }
            [pscustomobject]@{
                Version            = $_.Version
                Build              = $_.Build
                DisplayVersion     = $_.DisplayVersion
                OS                 = $_.OS
                Name               = $name
                Source             = 'Legacy Manifest'
                SourceFamily       = 'LegacyManifest'
                DiscoverySource    = 'Pinned Manifest'
                SourceId           = if ($preferredSource) { $preferredSource.SourceId } else { $null }
                Health             = $health
                HealthReason       = $healthReason
                Selectable         = ($sources.Count -gt 0)
                AutoEligible       = ($autoEligibleSources.Count -gt 0)
                Available          = $true
                SupportsWU         = $supportsWu
                SupportsFido       = $supportsFido
                SupportsCatalog    = $supportsCatalog
                SupportsMct        = $supportsMct
                SourceIds          = @($sources | ForEach-Object { $_.SourceId } | Where-Object { $_ })
                Sources            = @($sources)
            }
        }
    )
}

function Get-LegacyWindows10ReleaseInfos {
    <#
    .SYNOPSIS
        Returns normalized legacy Windows 10 discovery objects.
    #>
    foreach ($entry in Get-LegacyWindows10MediaManifest) {
        [pscustomobject]@{
            Version         = $entry.Version
            Build           = $entry.Build
            LatestBuild     = $entry.Build
            DisplayVersion  = $entry.DisplayVersion
            OS              = $entry.OS
            Name            = $entry.Name
            Source          = $entry.Source
            SourceFamily    = $entry.SourceFamily
            DiscoverySource = $entry.DiscoverySource
            Available       = $entry.Available
            SupportsWU      = $entry.SupportsWU
            SupportsFido    = $entry.SupportsFido
            SupportsCatalog = $entry.SupportsCatalog
            SupportsMct     = $entry.SupportsMct
        }
    }
}

function Add-UniqueRemoteVersion {
    param(
        [System.Collections.Generic.List[object]]$List,
        [object]$Item
    )

    if (-not $Item) {
        return
    }

    $version = [string]$Item.Version
    if (-not $version) {
        return
    }

    $existing = $List | Where-Object { [string]$_.Version -eq $version } | Select-Object -First 1
    if ($existing) {
        if ($Item.PSObject.Properties.Name -contains 'Sources' -and $Item.Sources) {
            $existingSources = @()
            if ($existing.PSObject.Properties.Name -contains 'Sources' -and $existing.Sources) {
                $existingSources = @($existing.Sources)
            }
            foreach ($source in @($Item.Sources)) {
                if (-not $source) { continue }
                $sourceId = if ($source.PSObject.Properties.Name -contains 'SourceId') { $source.SourceId } else { $null }
                $sourceUrl = if ($source.PSObject.Properties.Name -contains 'Url') { $source.Url } else { $null }
                $duplicate = $false
                foreach ($existingSource in $existingSources) {
                    $existingSourceId = if ($existingSource.PSObject.Properties.Name -contains 'SourceId') { $existingSource.SourceId } else { $null }
                    $existingSourceUrl = if ($existingSource.PSObject.Properties.Name -contains 'Url') { $existingSource.Url } else { $null }
                    if ($sourceId -and $existingSourceId -and $sourceId -eq $existingSourceId -and $sourceUrl -eq $existingSourceUrl) {
                        $duplicate = $true
                        break
                    }
                    if (-not $sourceId -and $sourceUrl -and $sourceUrl -eq $existingSourceUrl) {
                        $duplicate = $true
                        break
                    }
                }
                if (-not $duplicate) {
                    $existingSources += $source
                }
            }
            if ($existing.PSObject.Properties.Name -contains 'Sources') {
                $existing.Sources = @($existingSources)
            } else {
                $existing | Add-Member -NotePropertyName Sources -NotePropertyValue @($existingSources) -Force
            }
        }

        foreach ($propName in @('SourceId','Health','HealthReason','Selectable','AutoEligible','SourceIds')) {
            if ($Item.PSObject.Properties.Name -contains $propName) {
                if ($existing.PSObject.Properties.Name -contains $propName) {
                    $existing.$propName = $Item.$propName
                } else {
                    $existing | Add-Member -NotePropertyName $propName -NotePropertyValue $Item.$propName -Force
                }
            }
        }
        return $false
    }

    [void]$List.Add($Item)
    return $true
}

function Get-RemoteAvailableVersions {
    <#
    .SYNOPSIS
        Discovers available Windows versions from multiple sources:
        1. Direct Windows Update metadata client
        2. Microsoft Fido API (official download page, fewer builds but simpler)
        3. Local legacy Windows 10 manifest sourced from community-maintained media data
        Returns array of version info objects with Build, Version, OS, Name, etc.
    #>

    $available = [System.Collections.Generic.List[object]]::new()

    # =================================================================
    # Source 1: Direct Windows Update metadata client
    # =================================================================
    Write-Log '  Querying direct Windows Update metadata for available Windows builds...'

    $versionTargets = @(
        '25H2',
        '24H2',
        '23H2',
        '22H2',
        'W10_21H2',
        'W10_22H2'
    )

    $wuWorked = $false
    foreach ($targetVersion in $versionTargets) {
        try {
            $release = Get-WindowsFeatureReleaseInfo -TargetVersion $targetVersion -Arch 'amd64'
            if ($release) {
                [void]$available.Add($release)
                Write-Log "  $($release.Version): $($release.Name) (WU Direct)" -Level SUCCESS
                $wuWorked = $true
            }
            Start-Sleep -Milliseconds 400
        } catch {
            Write-Log "  ${targetVersion}: direct WU query failed -- $_" -Level DEBUG
        }
    }

    # =================================================================
    # Source 2: Microsoft Fido API (fallback if direct WU path is unavailable)
    # =================================================================
    if (-not $wuWorked) {
        Write-Log '  Direct Windows Update metadata unavailable. Trying Microsoft download API...'

        $fidoProducts = @(
            @{ EditionId = 3262; Version = '25H2'; Build = 26200; OS = 'Windows 11'; Name = 'Windows 11 25H2 x64' }
            @{ EditionId = 3113; Version = '24H2'; Build = 26100; OS = 'Windows 11'; Name = 'Windows 11 24H2 x64' }
            @{ EditionId = 2935; Version = '23H2'; Build = 22631; OS = 'Windows 11'; Name = 'Windows 11 23H2 x64' }
            @{ EditionId = 2618; Version = 'W10_22H2'; Build = 19045; OS = 'Windows 10'; Name = 'Windows 10 22H2 x64' }
        )

        $profileId = '606624d44113'
        foreach ($product in $fidoProducts) {
            try {
                $sessionId = [guid]::NewGuid().ToString()
                Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sessionId" -ErrorAction SilentlyContinue | Out-Null

                $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profileId&productEditionId=$($product.EditionId)&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$sessionId"
                $rawContent = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 $skuUrl -ErrorAction Stop).Content
                $skuResponse = $rawContent | ConvertFrom-Json -ErrorAction Stop

                $skus = if ($skuResponse.Skus) { $skuResponse.Skus } else { $null }
                if ($skus -and $skus.Count -gt 0) {
                    $engSku = $skus | Where-Object { $_.Language -eq 'English International' } | Select-Object -First 1
                    $fileName = if ($engSku -and $engSku.FriendlyFileNames) { $engSku.FriendlyFileNames[0] } else { '' }

                    [void]$available.Add(@{
                        Version          = $product.Version
                        Build            = $product.Build
                        OS               = $product.OS
                        Name             = $product.Name
                        LangCount        = $skus.Count
                        FriendlyFileName = $fileName
                        Source           = 'Microsoft API'
                        Available        = $true
                    })
                    Write-Log "  $($product.Version): $($product.Name) -- $($skus.Count) languages (Fido)" -Level SUCCESS
                }
            } catch {
                Write-Log "  $($product.Version): Fido query failed -- $_" -Level DEBUG
            }
        }
    }

    foreach ($legacyRelease in Get-LegacyWindows10ReleaseInfos) {
        if (Add-UniqueRemoteVersion -List $available -Item $legacyRelease) {
            Write-Log "  $($legacyRelease.Version): $($legacyRelease.Name) (Legacy manifest)" -Level SUCCESS
        }
    }

    return @($available)
}

function Get-DirectIsoDownloadUrl {
    <#
    .SYNOPSIS
        Gets a direct ISO download URL from Microsoft's software-download API.
        Implements the full Fido flow including ov-df.microsoft.com handshake
        (the "Sentinel" authentication that prevents unauthorized API access).
        Returns a time-limited (24h) direct download URL or $null.
    #>
    param(
        [string]$Language = 'English International',
        [string]$Arch = 'x64',
        [string]$Version = '25H2'
    )

    # Edition IDs per version (from Fido)
    $editionIds = @{
        '25H2'      = 3262
        '24H2'      = 3113
        '23H2'      = 2935
        '22H2'      = 2935
        '21H2'      = 2935
        'W10_22H2'  = 2618
        'W10_21H2'  = 2618
        'W10_20H2'  = 2618
    }
    $editionId = $editionIds[$Version]
    if (-not $editionId) { $editionId = 3262 }

    $profileId  = '606624d44113'
    $instanceId = '560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175'
    $sessionId  = [guid]::NewGuid().ToString()
    $referer = if ($Version -like 'W10_*') { 'https://www.microsoft.com/software-download/windows10ISO' } else { 'https://www.microsoft.com/software-download/windows11' }
    $timeout = 20

    Write-Log "  Requesting ISO from Microsoft (Edition $editionId / $Version / $Language)..."

    try {
        # Step 1: Whitelist session via vlscppe
        Write-Log '  [1/4] Whitelisting session...' -Level DEBUG
        Invoke-WebRequest -UseBasicParsing -TimeoutSec $timeout `
            "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sessionId" -ErrorAction SilentlyContinue | Out-Null

        # Step 2: ov-df handshake -- THIS IS REQUIRED to pass Sentinel
        # Fetches mdt.js to get 'w' (token) and 'rticks' (timestamp), then posts them back.
        # Without this, the download link API returns "SentinelReject".
        Write-Log '  [2/4] ov-df authentication handshake...' -Level DEBUG
        $ovUrl = "https://ov-df.microsoft.com/mdt.js?instanceId=$instanceId&PageId=si&session_id=$sessionId"
        $ovResp = Invoke-RestMethod -UseBasicParsing -TimeoutSec $timeout $ovUrl -ErrorAction Stop

        $w = $null; $rticks = $null
        if ($ovResp -match '[?&]w=([A-F0-9]+)') { $w = $matches[1] }
        if ($ovResp -match 'rticks\=\"\+?(\d+)') { $rticks = $matches[1] }

        if (-not $w -or -not $rticks) {
            Write-Log '  Could not extract ov-df tokens (w/rticks).' -Level WARN
            return $null
        }

        # Post back the ov-df reply with extracted tokens
        $epoch = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        $ovReplyUrl = "https://ov-df.microsoft.com/?session_id=$sessionId&CustomerId=$instanceId&PageId=si&w=$w&mdt=$epoch&rticks=$rticks"
        Invoke-WebRequest -UseBasicParsing -TimeoutSec $timeout $ovReplyUrl -ErrorAction SilentlyContinue | Out-Null
        Write-Log '  ov-df handshake complete.' -Level DEBUG

        # Step 3: Get SKU info
        Write-Log '  [3/4] Getting language SKUs...' -Level DEBUG
        $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition"
        $skuUrl += "?profile=$profileId&productEditionId=$editionId&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$sessionId"
        $rawContent = (Invoke-WebRequest -UseBasicParsing -TimeoutSec $timeout $skuUrl -ErrorAction Stop).Content
        $skuResponse = $rawContent | ConvertFrom-Json -ErrorAction Stop

        $skus = if ($skuResponse.Skus) { $skuResponse.Skus } else { $skuResponse }
        if (-not $skus -or $skus.Count -eq 0) {
            Write-Log '  No SKUs returned.' -Level WARN
            return $null
        }

        $skuMatch = $skus | Where-Object { $_.Language -eq $Language } | Select-Object -First 1
        if (-not $skuMatch) { $skuMatch = $skus | Where-Object { $_.Language -match 'English' } | Select-Object -First 1 }
        if (-not $skuMatch) { $skuMatch = $skus[0] }

        Write-Log "  SKU: $($skuMatch.Language) (ID: $($skuMatch.Id))" -Level DEBUG

        # Step 4: Get download links (Sentinel passes now because of ov-df)
        Write-Log '  [4/4] Getting download link...' -Level DEBUG
        $dlUrl = "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku"
        $dlUrl += "?profile=$profileId&productEditionId=undefined&SKU=$($skuMatch.Id)&friendlyFileName=undefined&Locale=en-US&sessionID=$sessionId"

        $dlContent = (Invoke-WebRequest -Headers @{ 'Referer' = $referer } -UseBasicParsing -TimeoutSec $timeout $dlUrl -ErrorAction Stop).Content
        $dlResponse = $dlContent | ConvertFrom-Json -ErrorAction Stop

        # Check for errors -- use PSObject.Properties to avoid strict mode throwing on missing property
        $hasErrors = ($dlResponse.PSObject.Properties.Name -contains 'Errors') -and $dlResponse.Errors
        if ($hasErrors) {
            $errMsg = ($dlResponse.Errors | ForEach-Object { $_.Value }) -join '; '
            Write-Log "  API error: $errMsg" -Level WARN
            return $null
        }

        # Extract ISO link -- response key is ProductDownloadOptions (not ProductDownloadLinks)
        $isoLink = $null
        $hasOptions = $dlResponse.PSObject.Properties.Name -contains 'ProductDownloadOptions'
        $hasLinks = $dlResponse.PSObject.Properties.Name -contains 'ProductDownloadLinks'
        $options = $null
        if ($hasOptions) { $options = $dlResponse.ProductDownloadOptions }
        elseif ($hasLinks) { $options = $dlResponse.ProductDownloadLinks }

        if (-not $options) {
            # Dump available properties for debugging
            $propNames = $dlResponse.PSObject.Properties.Name -join ', '
            Write-Log "  Response properties: $propNames" -Level DEBUG
            Write-Log "  Raw (first 300): $($dlContent.Substring(0, [math]::Min(300, $dlContent.Length)))" -Level DEBUG
            # Try to find any URL in the raw content
            if ($dlContent -match '(https://[^"''>\s]+\.iso[^"''>\s]*)') {
                $isoLink = $matches[1]
                Write-Log "  Extracted ISO URL from raw response." -Level DEBUG
            }
        } else {
            foreach ($opt in $options) {
                $uri = $null
                if ($opt.PSObject.Properties.Name -contains 'Uri') { $uri = $opt.Uri }
                if (-not $uri -and $opt.PSObject.Properties.Name -contains 'Url') { $uri = $opt.Url }
                if ($uri -and $uri -match '\.iso') {
                    $isoLink = $uri
                    break
                }
            }
        }

        if ($isoLink) {
            # Extract filename from URL for display
            $fileName = if ($isoLink -match '/([^/?]+\.iso)') { $matches[1] } else { 'Windows.iso' }
            Write-Log "  Direct ISO URL obtained: $fileName (valid ~24h)" -Level SUCCESS
            return $isoLink
        } else {
            Write-Log '  No ISO link found in API response.' -Level WARN
            return $null
        }
    } catch {
        Write-Log "  Microsoft API failed: $_" -Level WARN
        return $null
    }
}

function Get-ReleaseEsd {
    <#
    .SYNOPSIS
        Compatibility wrapper for the direct metadata download method.
        Uses the local Windows Update metadata client to get direct Microsoft CDN ESD URLs.

        Returns a hashtable with Url, Sha1, Size, FileName or $null.
    #>
    param(
        [string]$Version = '25H2',
        [string]$Language = 'en-us',
        [string]$Edition = 'professional'
    )

    Write-Log "  direct metadata client: Fetching latest $Version update ($Language/$Edition)..."

    try {
        $result = Get-WindowsFeatureFiles -TargetVersion $Version -Arch 'amd64' -Language $Language -Edition $Edition
        if (-not $result) {
            Write-Log '  direct metadata client: No ESD files returned for this build.' -Level WARN
            return $null
        }

        $totalSize = (($result.AllEsds | Measure-Object -Property Size -Sum).Sum)
        Write-Log "  direct metadata client: $($result.AllEsds.Count) ESD files available ($([math]::Round($totalSize / 1MB)) MB total)" -Level DEBUG

        if (-not $result.Sha1) {
            Write-Log '  direct metadata client: Selected ESD did not expose a usable SHA1 digest.' -Level WARN
        }

        $sizeMB = [math]::Round($result.Size / 1MB)
        Write-Log "  direct metadata client: Edition ESD: $($result.FileName) ($sizeMB MB)" -Level SUCCESS
        Write-Log "  direct metadata client: URL: $($result.Url.Substring(0, [math]::Min(100, $result.Url.Length)))..." -Level DEBUG
        return $result
    } catch {
        Write-Log "  direct metadata client failed: $_" -Level WARN
        return $null
    }
}

function Get-EsdDownloadFromCatalog {
    <#
    .SYNOPSIS
        Downloads Microsoft's products.cab catalog, extracts ESD download URLs
        with SHA1 hashes for the requested Windows 11 version and language.
        Returns a hashtable with Url, Sha1, Size, FileName or $null on failure.

        IMPORTANT: The public products.cab catalogs are version-specific.
        Only 22H2 and 23H2 have known catalog URLs. For 24H2/25H2 the catalog
        is embedded in the MCT executable and not publicly available.
        This function will return $null for versions without a known catalog,
        and the caller should fall back to the ISO API or MCT methods.
    #>
    param(
        [ValidateSet('22H2','23H2','24H2','25H2')]
        [string]$Version = '25H2',
        [string]$Language = 'en-us',
        [string]$Arch = 'x64',
        [string]$Edition = 'Professional'
    )

    # Products.cab URLs -- only versions with known public catalog URLs
    # 24H2 and 25H2 do NOT have public catalog URLs (embedded in MCT binary)
    $catalogUrls = @{
        '22H2' = 'https://download.microsoft.com/download/b/1/9/b19bd7fd-78c4-4f88-8c40-3e52aee143c2/products_win11_20230510.cab.cab'
        '23H2' = 'https://download.microsoft.com/download/6/2/b/62b47bc5-1b28-4bfa-9422-e7a098d326d4/products_win11_20231208.cab'
    }

    $cabUrl = $catalogUrls[$Version]
    if (-not $cabUrl) {
        Write-Log "  No public ESD catalog available for $Version (only 22H2/23H2 have known catalogs)." -Level WARN
        Write-Log '  Will use ISO API or MCT for this version instead.' -Level DEBUG
        return $null
    }

    $cabPath = Join-Path $DownloadPath 'products.cab'
    $xmlPath = Join-Path $DownloadPath 'products.xml'
    $extrac32 = Join-Path $env:SystemRoot 'System32\extrac32.exe'

    Write-Log "  Downloading Microsoft ESD catalog for $Version..."

    try {
        # Download products.cab
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $cabUrl -OutFile $cabPath -UseBasicParsing -ErrorAction Stop
        $ProgressPreference = 'Continue'

        # Extract XML from CAB using extrac32 (works everywhere, no Git Bash conflict)
        if (Test-Path $extrac32) {
            & $extrac32 /Y /E $cabPath /L $DownloadPath 2>$null | Out-Null
        } else {
            # Fallback to expand.exe with full path
            $expandExe = Join-Path $env:SystemRoot 'System32\expand.exe'
            & $expandExe $cabPath "-F:products.xml" $DownloadPath 2>$null | Out-Null
        }

        if (-not (Test-Path $xmlPath)) {
            Write-Log '  Could not extract products.xml from catalog.' -Level WARN
            return $null
        }

        $xml = [xml](Get-Content $xmlPath -Raw -ErrorAction Stop)

        # Find all valid entries for the requested version/language
        $nodes = $xml.SelectNodes('//Package[@Culture]')
        if (-not $nodes) {
            $nodes = $xml.SelectNodes('//Package')
        }

        $matches = @()
        foreach ($node in $nodes) {
            $culture = $node.Culture
            $name = $node.Name
            $url = $node.Url
            $size = if ($node.Size) { [long]$node.Size } else { 0 }
            $sha1 = if ($node.Hash) { $node.Hash } else { $null }

            if ($url -and $url -match '\.esd') {
                if ($culture -and $culture -eq $Language) {
                    $matches += @{
                        Url      = $url
                        Sha1     = $sha1
                        Size     = $size
                        FileName = if ($name) { $name } else { ([System.IO.Path]::GetFileName($url)) }
                    }
                } elseif (-not $culture -and $name -match $Edition) {
                    $matches += @{
                        Url      = $url
                        Sha1     = $sha1
                        Size     = $size
                        FileName = if ($name) { $name } else { ([System.IO.Path]::GetFileName($url)) }
                    }
                }
            }
        }

        if ($matches.Count -eq 0) {
            Write-Log '  No matching ESD entries found in catalog.' -Level WARN
            return $null
        }

        $best = $matches | Select-Object -First 1
        Write-Log "  ESD catalog selected: $($best.FileName)" -Level SUCCESS
        return $best
    } catch {
        Write-Log "  Catalog download failed: $_" -Level WARN
        return $null
    }
}
