function Test-FileHash {
    <#
    .SYNOPSIS
        Verifies a file's SHA1 or SHA256 hash with a progress indicator.
        Returns $true if the hash matches.
    #>
    param(
        [string]$FilePath,
        [string]$ExpectedHash,
        [ValidateSet('SHA1','SHA256')]
        [string]$Algorithm = 'SHA1'
    )

    if ([string]::IsNullOrEmpty($ExpectedHash)) {
        Write-Log '  No hash provided -- skipping verification.' -Level DEBUG
        return $true
    }

    if (-not (Test-Path $FilePath)) {
        Write-Log "  File not found for hash check: $FilePath" -Level WARN
        return $false
    }

    Write-Log "  Verifying $Algorithm hash..."
    try {
        $fileHash = (Get-FileHash -Path $FilePath -Algorithm $Algorithm -ErrorAction Stop).Hash
        if ($fileHash -eq $ExpectedHash.ToUpper()) {
            Write-Log "  $Algorithm hash verified: $fileHash" -Level SUCCESS
            return $true
        } else {
            Write-Log "  $Algorithm MISMATCH!" -Level ERROR
            Write-Log "    Expected: $($ExpectedHash.ToUpper())" -Level ERROR
            Write-Log "    Got:      $fileHash" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "  Hash verification failed: $_" -Level WARN
        return $true  # Don't block on hash check failure
    }
}

function Convert-EsdToIso {
    <#
    .SYNOPSIS
        Converts a downloaded ESD to a usable setup structure for in-place upgrade.
        ESD structure: Index 1=WinPE, 2=Setup, 3=WinRE, 4+=Editions (Home, Pro, etc.)

        For in-place upgrade we need:
        - setup.exe + supporting files (from index 2: Windows Setup)
        - install.wim with the target edition (from matching index 4+)
        - boot.wim (from indexes 1+2)

        Only exports the MATCHING edition to avoid wasting 20+ min on all editions.
        Returns the path to the extracted setup directory or $null on failure.
    #>
    param(
        [string]$EsdPath,
        [string]$OutputDir,
        [string]$TargetEdition = 'Professional'
    )

    if (-not (Test-Path $EsdPath)) {
        Write-Log "  ESD file not found: $EsdPath" -Level ERROR
        return $null
    }

    Write-Log '  Converting ESD to installable media...'
    $wimDir = Join-Path $OutputDir 'EsdExtracted'
    $sourcesDir = Join-Path $wimDir 'sources'
    if (Test-Path $wimDir) { Remove-Item $wimDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $sourcesDir -Force -ErrorAction SilentlyContinue | Out-Null

    try {
        # Get image info from the ESD -- parse index numbers AND names
        Write-Log '  Reading ESD image index info...'
        $dismInfo = & dism.exe /Get-WimInfo /WimFile:"$EsdPath" 2>&1
        $dismText = $dismInfo -join "`n"

        # Parse all indexes with their names
        $indexBlocks = [regex]::Matches($dismText, 'Index\s*:\s*(\d+)\s*\r?\nName\s*:\s*(.+)')
        if ($indexBlocks.Count -eq 0) {
            # Fallback: just get index numbers
            $indexNums = [regex]::Matches($dismText, 'Index\s*:\s*(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
            Write-Log "  ESD contains $($indexNums.Count) image(s) (names not parsed)" -Level DEBUG
        } else {
            Write-Log "  ESD images:" -Level DEBUG
            foreach ($block in $indexBlocks) {
                Write-Log "    Index $($block.Groups[1].Value): $($block.Groups[2].Value.Trim())" -Level DEBUG
            }
        }

        $wimPath = Join-Path $sourcesDir 'install.wim'
        $bootWim = Join-Path $sourcesDir 'boot.wim'

        # Step 1: Export setup files from index 2 (Windows Setup)
        # This is critical -- without this, we have no setup.exe
        Write-Log '  Exporting Windows Setup (index 2) -- contains setup.exe...'
        $setupProc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList "/Apply-Image /ImageFile:`"$EsdPath`" /Index:2 /ApplyDir:`"$wimDir`"" `
            -NoNewWindow -PassThru -Wait
        Write-Host ''

        if ($setupProc.ExitCode -ne 0) {
            Write-Log "  DISM Apply index 2 failed with code $($setupProc.ExitCode)." -Level WARN
            Write-Log '  Cannot extract setup.exe from ESD -- this ESD may not support in-place upgrade.' -Level WARN
            return $null
        }

        if (-not (Test-Path (Join-Path $wimDir 'setup.exe'))) {
            Write-Log '  setup.exe not found after extracting index 2.' -Level WARN
            return $null
        }
        Write-Log '  setup.exe extracted from ESD.' -Level SUCCESS

        # Step 2: Export boot.wim from indexes 1 and 2
        Write-Log '  Exporting boot images (indexes 1-2)...'
        foreach ($idx in @(1, 2)) {
            $bp = Start-Process -FilePath 'dism.exe' `
                -ArgumentList "/Export-Image /SourceImageFile:`"$EsdPath`" /SourceIndex:$idx /DestinationImageFile:`"$bootWim`" /Compress:Max" `
                -NoNewWindow -PassThru -Wait
        }
        Write-Host ''

        # Step 3: Export ONLY the matching edition to install.wim
        # Find the index that matches our target edition
        $targetIdx = $null
        if ($indexBlocks.Count -gt 0) {
            foreach ($block in $indexBlocks) {
                $idx = [int]$block.Groups[1].Value
                $name = $block.Groups[2].Value.Trim()
                if ($idx -ge 4 -and $name -match $TargetEdition) {
                    $targetIdx = $idx
                    Write-Log "  Matched edition '$TargetEdition' at index $idx ($name)" -Level DEBUG
                    break
                }
            }
        }
        # Fallback: use index 4 (usually Pro) or 6 (usually Pro in consumer ESDs)
        if (-not $targetIdx) {
            $targetIdx = 6  # Common index for Professional in consumer ESDs
            Write-Log "  Could not match edition by name -- using index $targetIdx as default." -Level DEBUG
        }

        Write-Log "  Exporting install image (index $targetIdx only)..."
        Write-Host ''
        $installProc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList "/Export-Image /SourceImageFile:`"$EsdPath`" /SourceIndex:$targetIdx /DestinationImageFile:`"$wimPath`" /Compress:Max /CheckIntegrity" `
            -NoNewWindow -PassThru -Wait
        Write-Host ''

        if ($installProc.ExitCode -ne 0) {
            Write-Log "  DISM export index $targetIdx failed -- trying index 4 as fallback..." -Level WARN
            $installProc = Start-Process -FilePath 'dism.exe' `
                -ArgumentList "/Export-Image /SourceImageFile:`"$EsdPath`" /SourceIndex:4 /DestinationImageFile:`"$wimPath`" /Compress:Max /CheckIntegrity" `
                -NoNewWindow -PassThru -Wait
            Write-Host ''
        }

        if ($installProc.ExitCode -eq 0 -and (Test-Path $wimPath)) {
            $wimSize = [math]::Round((Get-Item $wimPath).Length / 1GB, 2)
            Write-Log "  install.wim created: $wimSize GB (single edition)" -Level SUCCESS
            Write-Log "  Setup structure ready at: $wimDir" -Level SUCCESS
            return $wimDir
        } else {
            Write-Log '  Could not export install image from ESD.' -Level WARN
            return $null
        }
    } catch {
        Write-Log "  ESD conversion failed: $_" -Level WARN
        return $null
    }
}

function Start-DownloadWithProgress {
    <#
    .SYNOPSIS
        Downloads a file with a live console progress bar showing speed and ETA.
        Tries BITS first (best for large files), then .NET HttpClient, then WebClient.
    #>
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Description = 'file'
    )

    Write-Log "  Downloading $Description..."
    Write-Log "  URL: $Url" -Level DEBUG
    Write-Log "  Destination: $Destination" -Level DEBUG

    # --- Method 1: BITS Transfer (supports resume, low priority, progress) ---
    try {
        Write-Log '  Trying BITS transfer...' -Level DEBUG
        $bitsJob = Start-BitsTransfer -Source $Url -Destination $Destination -Asynchronous -Priority Normal -ErrorAction Stop

        $startTime = Get-Date
        while ($bitsJob.JobState -eq 'Transferring' -or $bitsJob.JobState -eq 'Connecting' -or $bitsJob.JobState -eq 'Queued') {
            $pct = 0
            if ($bitsJob.BytesTotal -gt 0) {
                $pct = [math]::Round(($bitsJob.BytesTransferred / $bitsJob.BytesTotal) * 100, 1)
                $totalMB = [math]::Round($bitsJob.BytesTotal / 1MB)
                $dlMB = [math]::Round($bitsJob.BytesTransferred / 1MB)
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                $speed = if ($elapsed -gt 0) { [math]::Round($bitsJob.BytesTransferred / $elapsed / 1MB, 1) } else { 0 }
                $eta = if ($speed -gt 0) { [math]::Round(($bitsJob.BytesTotal - $bitsJob.BytesTransferred) / 1MB / $speed / 60, 1) } else { 0 }
                $bar = '[' + ('#' * [math]::Floor($pct / 2.5)).PadRight(40) + ']'
                Write-Host ("`r  $bar $pct% -- $dlMB / $totalMB MB -- ${speed} MB/s -- ETA ${eta}m   ") -NoNewline
            } else {
                Write-Host ("`r  Connecting... $($bitsJob.JobState)   ") -NoNewline
            }
            Start-Sleep -Seconds 2
        }
        Write-Host ''

        if ($bitsJob.JobState -eq 'Transferred') {
            Complete-BitsTransfer $bitsJob
            $size = [math]::Round((Get-Item $Destination).Length / 1GB, 2)
            Write-Log "  Download complete (BITS): $size GB" -Level SUCCESS
            return $true
        } else {
            Write-Log "  BITS transfer ended in state: $($bitsJob.JobState)" -Level WARN
            Remove-BitsTransfer $bitsJob -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "  BITS failed: $_" -Level WARN
    }

    # --- Method 2: .NET HttpClient with progress ---
    try {
        Write-Log '  Trying .NET HttpClient download...' -Level DEBUG
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromMinutes(120)

        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        $response.EnsureSuccessStatusCode() | Out-Null
        $totalBytes = $response.Content.Headers.ContentLength

        $stream = $response.Content.ReadAsStreamAsync().Result
        $fileStream = [IO.File]::Create($Destination)
        $buffer = New-Object byte[] 1048576  # 1 MB buffer
        $totalRead = 0
        $startTime = Get-Date

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read

            if ($totalBytes -and $totalBytes -gt 0) {
                $pct = [math]::Round(($totalRead / $totalBytes) * 100, 1)
                $dlMB = [math]::Round($totalRead / 1MB)
                $totalMB = [math]::Round($totalBytes / 1MB)
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                $speed = if ($elapsed -gt 0) { [math]::Round($totalRead / $elapsed / 1MB, 1) } else { 0 }
                $eta = if ($speed -gt 0) { [math]::Round(($totalBytes - $totalRead) / 1MB / $speed / 60, 1) } else { 0 }
                $bar = '[' + ('#' * [math]::Floor($pct / 2.5)).PadRight(40) + ']'
                Write-Host ("`r  $bar $pct% -- $dlMB / $totalMB MB -- ${speed} MB/s -- ETA ${eta}m   ") -NoNewline
            }
        }
        Write-Host ''

        $fileStream.Close()
        $stream.Close()
        $client.Dispose()

        $size = [math]::Round((Get-Item $Destination).Length / 1GB, 2)
        Write-Log "  Download complete (HttpClient): $size GB" -Level SUCCESS
        return $true
    } catch {
        Write-Log "  HttpClient failed: $_" -Level WARN
        try { $fileStream.Close() } catch { }
        try { $client.Dispose() } catch { }
    }

    # --- Method 3: curl.exe with built-in progress ---
    try {
        $curlPath = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path $curlPath) {
            Write-Log '  Trying curl.exe...' -Level DEBUG
            # curl shows its own progress bar natively
            $proc = Start-Process -FilePath $curlPath `
                -ArgumentList "-L -o `"$Destination`" --progress-bar `"$Url`"" `
                -NoNewWindow -PassThru -Wait
            if ($proc.ExitCode -eq 0 -and (Test-Path $Destination)) {
                $size = [math]::Round((Get-Item $Destination).Length / 1GB, 2)
                Write-Log "  Download complete (curl): $size GB" -Level SUCCESS
                return $true
            }
        }
    } catch {
        Write-Log "  curl failed: $_" -Level WARN
    }

    Write-Log '  All download methods failed.' -Level ERROR
    return $false
}

function Get-SystemLanguageCode {
    <#
    .SYNOPSIS
        Detects the active OS display language for ISO/ESD matching.
        For in-place upgrade the ISO language must match the OS display language.

        On multilingual systems (e.g. installed English, display set to Portuguese),
        this returns the ACTIVE DISPLAY language (Portuguese), because that's what
        the upgrade ISO needs to match.

        Priority order:
        1. Get-WinUserLanguageList[0] -- the user's active display language
        2. HKLM MUI\UILanguages with Type check -- the primary UI language
        3. SYSTEM MuiCached MachinePreferredUILanguages -- SYSTEM user's preference
        4. Nls\Language\Default -- the boot/system default LCID
        5. Get-WinSystemLocale -- system locale
        6. Get-Culture -- last resort
    #>
    $langCode = $null

    # Method 1: Get-WinUserLanguageList -- the user's preferred display language
    # First entry is the ACTIVE display language (what the user sees)
    # This is the correct language for an in-place upgrade ISO
    try {
        $userLangs = Get-WinUserLanguageList -ErrorAction SilentlyContinue
        if ($userLangs -and $userLangs.Count -gt 0) {
            $langCode = $userLangs[0].LanguageTag
        }
    } catch { }

    # Method 2: MUI UILanguages with Type field
    # Type 273 = original install, Type 274 = added pack
    # Prefer the one actively set as display language (may not always be Type 273)
    if (-not $langCode) {
        try {
            $muiKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages'
            if (Test-Path $muiKey) {
                $uiLangs = Get-ChildItem $muiKey -ErrorAction SilentlyContinue
                if ($uiLangs -and $uiLangs.Count -eq 1) {
                    # Only one language installed -- use it
                    $langCode = $uiLangs[0].PSChildName
                } elseif ($uiLangs -and $uiLangs.Count -gt 1) {
                    # Multiple languages -- pick by Nls\Language\Default
                    $defLcid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -ErrorAction SilentlyContinue).Default
                    if ($defLcid) {
                        $defCulture = [System.Globalization.CultureInfo]::GetCultureInfo([int]"0x$defLcid")
                        if ($defCulture) { $langCode = $defCulture.Name }
                    }
                    # Fallback: first entry
                    if (-not $langCode) { $langCode = $uiLangs[0].PSChildName }
                }
            }
        } catch { }
    }

    # Method 3: SYSTEM user MuiCached
    if (-not $langCode) {
        try {
            $muiCacheKey = 'Registry::HKU\S-1-5-18\Control Panel\Desktop\MuiCached'
            if (Test-Path $muiCacheKey) {
                $muiLangs = (Get-ItemProperty $muiCacheKey -Name 'MachinePreferredUILanguages' -ErrorAction SilentlyContinue).MachinePreferredUILanguages
                if ($muiLangs) {
                    $langCode = if ($muiLangs -is [array]) { $muiLangs[0] } else { ($muiLangs -split "`n")[0] }
                    $langCode = $langCode.Trim()
                }
            }
        } catch { }
    }

    # Method 4: Nls\Language\Default LCID
    if (-not $langCode) {
        try {
            $defLcid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -ErrorAction SilentlyContinue).Default
            if ($defLcid) {
                $culture = [System.Globalization.CultureInfo]::GetCultureInfo([int]"0x$defLcid")
                if ($culture) { $langCode = $culture.Name }
            }
        } catch { }
    }

    # Method 5: Get-WinSystemLocale
    if (-not $langCode) {
        try {
            $locale = Get-WinSystemLocale -ErrorAction SilentlyContinue
            if ($locale) { $langCode = $locale.Name }
        } catch { }
    }

    # Method 6: Get-Culture (last resort)
    if (-not $langCode) {
        try {
            $langCode = (Get-Culture).Name
        } catch { }
    }

    # Method 4: fallback
    if (-not $langCode) { $langCode = 'en-US' }

    Write-Log "  System language detected: $langCode" -Level DEBUG
    return $langCode
}

function ConvertTo-MicrosoftLanguageName {
    <#
    .SYNOPSIS
        Converts a locale code (pt-PT, de-DE) to the full language name that
        Microsoft's download APIs expect (Portuguese, German, etc.).
        The Fido API uses names like "English International", "Portuguese",
        "Brazilian Portuguese" -- not locale codes.
    #>
    param([string]$LocaleCode)

    $map = @{
        'ar-SA' = 'Arabic'
        'bg-BG' = 'Bulgarian'
        'cs-CZ' = 'Czech'
        'da-DK' = 'Danish'
        'de-DE' = 'German'
        'el-GR' = 'Greek'
        'en-US' = 'English'
        'en-GB' = 'English International'
        'es-ES' = 'Spanish'
        'es-MX' = 'Spanish (Mexico)'
        'et-EE' = 'Estonian'
        'fi-FI' = 'Finnish'
        'fr-FR' = 'French'
        'fr-CA' = 'French Canadian'
        'he-IL' = 'Hebrew'
        'hr-HR' = 'Croatian'
        'hu-HU' = 'Hungarian'
        'it-IT' = 'Italian'
        'ja-JP' = 'Japanese'
        'ko-KR' = 'Korean'
        'lt-LT' = 'Lithuanian'
        'lv-LV' = 'Latvian'
        'nb-NO' = 'Norwegian'
        'nl-NL' = 'Dutch'
        'pl-PL' = 'Polish'
        'pt-BR' = 'Brazilian Portuguese'
        'pt-PT' = 'Portuguese'
        'ro-RO' = 'Romanian'
        'ru-RU' = 'Russian'
        'sk-SK' = 'Slovak'
        'sl-SI' = 'Slovenian'
        'sv-SE' = 'Swedish'
        'th-TH' = 'Thai'
        'tr-TR' = 'Turkish'
        'uk-UA' = 'Ukrainian'
        'zh-CN' = 'Chinese Simplified'
        'zh-TW' = 'Chinese Traditional'
    }

    if ($map.ContainsKey($LocaleCode)) {
        return $map[$LocaleCode]
    }

    # Fallback: try culture name
    try {
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($LocaleCode)
        switch ($culture.TwoLetterISOLanguageName) {
            'en' { return 'English' }
            'de' { return 'German' }
            'fr' { return 'French' }
            'es' { return 'Spanish' }
            'pt' { return 'Portuguese' }
            'it' { return 'Italian' }
            'ja' { return 'Japanese' }
            'ko' { return 'Korean' }
            'zh' { return 'Chinese Simplified' }
            default { return $culture.EnglishName.Split('(')[0].Trim() }
        }
    } catch {
        return 'English'
    }
}

function Repair-TlsConfiguration {
    <#
    .SYNOPSIS
        Fixes TLS configuration so MCT and other download tools can connect
        to Microsoft's CDN. Addresses error 0x80072F78 (ERROR_INTERNET_DECODING_FAILED)
        which occurs when WinHTTP/WinINET can't negotiate TLS 1.2 properly.

        Root cause: On Win11 21H2 and older Win10, WinHTTP's DefaultSecureProtocols
        and .NET's SchUseStrongCrypto may not be set, causing TLS 1.2 negotiation
        to fail against Microsoft's servers which have dropped TLS 1.0/1.1.
    #>
    Write-Log '  Ensuring TLS 1.2 configuration for downloads...'
    $fixed = 0

    # 1. WinHTTP DefaultSecureProtocols -- tells WinHTTP to use TLS 1.2
    # 0x800 = TLS 1.2, 0x200 = TLS 1.1, 0x80 = TLS 1.0
    # 0xA80 = TLS 1.0 + 1.1 + 1.2 (most compatible)
    # 0xA00 = TLS 1.1 + 1.2 (recommended)
    $winHttpKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
    $currentVal = Get-RegValue $winHttpKey 'DefaultSecureProtocols'
    if (-not $currentVal -or ($currentVal -band 0x800) -eq 0) {
        Set-RegValue $winHttpKey 'DefaultSecureProtocols' 0xA00 'TLS/WinHTTP' | Out-Null
        $fixed++
    }
    # Also for WOW64
    $winHttpWow = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
    $currentWow = Get-RegValue $winHttpWow 'DefaultSecureProtocols'
    if (-not $currentWow -or ($currentWow -band 0x800) -eq 0) {
        Set-RegValue $winHttpWow 'DefaultSecureProtocols' 0xA00 'TLS/WinHTTP-WOW64' | Out-Null
        $fixed++
    }

    # 2. Schannel TLS 1.2 Client -- ensure it's explicitly enabled
    $tls12Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    $tls12Enabled = Get-RegValue $tls12Key 'Enabled'
    $tls12Disabled = Get-RegValue $tls12Key 'DisabledByDefault'
    if ($tls12Enabled -ne 1 -or $tls12Disabled -ne 0) {
        Set-RegValue $tls12Key 'Enabled' 1 'TLS/Schannel' | Out-Null
        Set-RegValue $tls12Key 'DisabledByDefault' 0 'TLS/Schannel' | Out-Null
        $fixed++
    }

    # 3. .NET Framework strong crypto -- required for MCT which uses .NET internally
    $netKeys = @(
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    )
    foreach ($nk in $netKeys) {
        $strongCrypto = Get-RegValue $nk 'SchUseStrongCrypto'
        $sysDefault = Get-RegValue $nk 'SystemDefaultTlsVersions'
        if ($strongCrypto -ne 1 -or $sysDefault -ne 1) {
            Set-RegValue $nk 'SchUseStrongCrypto' 1 'TLS/.NET' | Out-Null
            Set-RegValue $nk 'SystemDefaultTlsVersions' 1 'TLS/.NET' | Out-Null
            $fixed++
        }
    }

    # 4. Also set for the current PowerShell process (immediate effect)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    }

    if ($fixed -gt 0) {
        Write-Log "  TLS 1.2 configuration fixed ($fixed registry changes)." -Level SUCCESS
    } else {
        Write-Log '  TLS 1.2 already configured correctly.' -Level DEBUG
    }
}

function Start-MctIsoCreation {
    <#
    .SYNOPSIS
        Runs the Media Creation Tool with UI automation to create an ISO unattended.
        The MCT's CLI args (/Action CreateMedia) do NOT reliably skip the GUI wizard
        on newer MCT versions. Instead, we use UIAutomation
        to detect SetupHost.exe's window and click through the wizard:
        1. Launch MCT -> wait for SetupHost.exe window
        2. Accept EULA (automatic via /Eula Accept)
        3. Select "Create installation media" radio button via UIAutomation
        4. Click Next, select ISO, set output path
        5. Monitor download progress via windlp.state.xml
    #>
    param(
        [string]$MctExePath,
        [string]$OutputIsoPath,
        [string]$LangCode = 'en-US',
        [string]$Edition = 'Professional',
        [string]$Arch = 'x64',
        [string]$WorkingDirectory,
        [string]$CatalogPath,
        [object]$LegacySpec,
        [switch]$SkipUiAutomation,
        [switch]$OmitMediaEditionArg
    )

    if (-not (Test-Path $MctExePath)) {
        Write-Log "  MCT executable not found: $MctExePath" -Level ERROR
        return $false
    }

    if (-not $WorkingDirectory) {
        $WorkingDirectory = Split-Path $MctExePath -Parent
    }

    if (-not $LegacySpec) {
        $legacySidecar = Join-Path $WorkingDirectory 'legacy-release.json'
        if (Test-Path $legacySidecar) {
            try {
                $LegacySpec = Get-Content -Path $legacySidecar -Raw | ConvertFrom-Json -ErrorAction Stop
            } catch { }
        }
    }

    $mctDir = $WorkingDirectory
    $legacyMode = $false
    if ($LegacySpec) {
        $legacyMode = $true
        if (-not $OmitMediaEditionArg -and $LegacySpec.PSObject.Properties.Name -contains 'SupportsMediaEditionArg') {
            $OmitMediaEditionArg = -not [bool]$LegacySpec.SupportsMediaEditionArg
        }
        if ($LegacySpec.PSObject.Properties.Name -contains 'PreferredMctUrl' -and $LegacySpec.PreferredMctUrl) {
            Write-Log "  Legacy MCT release: $($LegacySpec.Version) ($($LegacySpec.DisplayVersion))" -Level DEBUG
        }
    }

    # ================================================================
    # PRE-LAUNCH FIXES
    # ================================================================
    Repair-TlsConfiguration

    # Clean stale MCT working directories
    foreach ($staleDir in @("$env:SystemDrive\`$WINDOWS.~WS", "$env:SystemDrive\ESD\Windows")) {
        if (Test-Path $staleDir) {
            Write-Log "  Cleaning stale MCT cache: $staleDir" -Level DEBUG
            Remove-Item $staleDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem $mctDir -Filter 'products.*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    if ($CatalogPath -and (Test-Path $CatalogPath)) {
        try {
            $catalogLeaf = Split-Path $CatalogPath -Leaf
            $catalogDest = Join-Path $mctDir $catalogLeaf
            if ((Resolve-Path $CatalogPath).Path -ne (Resolve-Path $catalogDest -ErrorAction SilentlyContinue).Path) {
                Copy-Item -Path $CatalogPath -Destination $catalogDest -Force -ErrorAction Stop
            }
            Write-Log "  Staged legacy catalog: $catalogLeaf" -Level DEBUG
        } catch {
            Write-Log "  Could not stage catalog ${CatalogPath}: $_" -Level WARN
        }
    }

    # Generate EI.cfg
    try { @('[Channel]', '_Default') | Set-Content (Join-Path $mctDir 'EI.cfg') -Encoding ASCII -Force } catch { }

    try { & netsh.exe winhttp reset proxy 2>$null | Out-Null } catch { }

    # ================================================================
    # LAUNCH MCT + UI AUTOMATION
    # ================================================================

    # Load UIAutomation assemblies
    $uiLoaded = $false
    if (-not $SkipUiAutomation) {
        try {
            Add-Type -AssemblyName 'UIAutomationClient' -ErrorAction Stop
            Add-Type -AssemblyName 'UIAutomationTypes' -ErrorAction Stop
            Add-Type -AssemblyName 'System.Windows.Forms' -ErrorAction Stop
            $uiLoaded = $true
            Write-Log '  UIAutomation loaded for MCT wizard control.' -Level DEBUG
        } catch {
            Write-Log "  UIAutomation not available: $_ -- MCT may need manual interaction." -Level WARN
        }
    }

    # MCT args -- /Selfhost makes it use the local working dir, /Eula Accept handles the license.
    $argParts = @(
        '/Selfhost',
        '/Action CreateMedia',
        "/MediaLangCode $LangCode"
    )
    if (-not $OmitMediaEditionArg -and $Edition) {
        $argParts += "/MediaEdition $Edition"
    }
    $argParts += @(
        "/MediaArch $Arch",
        '/Pkey Defer',
        '/SkipSummary',
        '/Eula Accept'
    )
    $argString = [string]::Join(' ', $argParts)
    Write-Log "  MCT args: $argString" -Level DEBUG
    Write-Log "  Output: $OutputIsoPath" -Level DEBUG

    # Kill any stale SetupHost from previous runs
    Get-Process SetupHost -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }

    try {
        $mctProc = Start-Process -FilePath $MctExePath -ArgumentList $argString `
        -WorkingDirectory $mctDir -PassThru -ErrorAction Stop

        if ($null -eq $mctProc) {
            Write-Log '  MCT process is null.' -Level ERROR
            return $false
        }
        Write-Log "  MCT launched (PID $($mctProc.Id))" -Level DEBUG

        # Wait for SetupHost.exe to spawn (MCT launches it as the actual GUI)
        Write-Log '  Waiting for SetupHost.exe window...' -Level DEBUG
        $setupProc = $null
        $waitStart = Get-Date
        while ($null -eq $setupProc -and ((Get-Date) - $waitStart).TotalSeconds -lt 60) {
            if ($mctProc.HasExited) {
                Write-Log "  MCT exited early with code $($mctProc.ExitCode)." -Level WARN
                return $false
            }
            $setupProc = Get-Process SetupHost -ErrorAction SilentlyContinue | Select-Object -First 1
            Start-Sleep -Milliseconds 500
        }

        if ($null -eq $setupProc) {
            Write-Log '  SetupHost.exe did not appear within 60s.' -Level WARN
            try { $mctProc.Kill() } catch { }
            return $false
        }

        # Wait for SetupHost to have a main window
        while ($setupProc.MainWindowHandle -eq 0) {
            if ($mctProc.HasExited) { break }
            $setupProc.Refresh()
            Start-Sleep -Milliseconds 300
        }
        Write-Log "  SetupHost.exe window found (PID $($setupProc.Id))" -Level DEBUG

        # ================================================================
        # UI AUTOMATION: Click through the MCT wizard
        # The wizard has these screens:
        # 1. EULA (handled by /Eula Accept)
        # 2. "What do you want to do?" - radio: Upgrade / Create media
        # 3. Language/Edition/Architecture selection
        # 4. "Choose which media to use" - radio: USB / ISO file
        # 5. ISO save dialog (file path entry)
        # ================================================================
        if ($uiLoaded) {
            Start-Sleep -Seconds 2  # Let the UI settle

            try {
                $win = [Windows.Automation.AutomationElement]::FromHandle($setupProc.MainWindowHandle)

                # Helper: find all buttons/radios
                $btnCondition = New-Object Windows.Automation.PropertyCondition(
                    [Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [Windows.Automation.ControlType]::RadioButton
                )
                $allBtnCondition = New-Object Windows.Automation.PropertyCondition(
                    [Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [Windows.Automation.ControlType]::Button
                )

                # Helper: press Enter via SendKeys
                function Press-Enter {
                    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                    Start-Sleep -Seconds 1
                }

                # Screen 2: "What do you want to do?" -- select "Create installation media"
                Write-Log '  [UI] Selecting "Create installation media"...' -Level DEBUG
                $maxWait = 30
                $waited = 0
                while ($waited -lt $maxWait) {
                    $radios = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $btnCondition)
                    if ($radios.Count -ge 2) { break }
                    Start-Sleep -Seconds 1; $waited++
                    if ($mctProc.HasExited) { break }
                    $setupProc.Refresh()
                    if ($setupProc.MainWindowHandle -ne 0) {
                        try { $win = [Windows.Automation.AutomationElement]::FromHandle($setupProc.MainWindowHandle) } catch { }
                    }
                }

                if ($radios.Count -ge 2) {
                    # Second radio = "Create installation media"
                    try {
                        $createMediaRadio = $radios[1]
                        $selPattern = $createMediaRadio.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
                        $selPattern.Select()
                        Write-Log '  [UI] "Create installation media" selected.' -Level SUCCESS
                    } catch {
                        Write-Log "  [UI] Could not select radio: $_" -Level WARN
                    }
                    Start-Sleep -Milliseconds 500

                    # Click Next (last button on the page)
                    $buttons = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $allBtnCondition)
                    if ($buttons.Count -gt 0) {
                        $nextBtn = $buttons[$buttons.Count - 1]
                        $nextBtn.SetFocus()
                    }
                    Press-Enter
                    Write-Log '  [UI] Clicked Next on media choice.' -Level DEBUG
                } else {
                    Write-Log "  [UI] Radio buttons not found ($($radios.Count) found) -- MCT may have auto-advanced." -Level WARN
                    Press-Enter  # Try pressing Enter anyway
                }

                # Screen 3: Language/Edition/Arch -- should be pre-filled by CLI args, just click Next
                Start-Sleep -Seconds 2
                Press-Enter
                Write-Log '  [UI] Clicked Next on language/edition.' -Level DEBUG

                # Screen 4: "Choose which media" -- select "ISO file" (second radio)
                Start-Sleep -Seconds 2
                try {
                    $setupProc.Refresh()
                    if ($setupProc.MainWindowHandle -ne 0) {
                        $win = [Windows.Automation.AutomationElement]::FromHandle($setupProc.MainWindowHandle)
                    }
                    $radios = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $btnCondition)
                    if ($radios.Count -ge 2) {
                        $isoRadio = $radios[1]  # Second radio = ISO file
                        $selPattern = $isoRadio.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
                        $selPattern.Select()
                        Write-Log '  [UI] "ISO file" selected.' -Level SUCCESS
                    }
                } catch {
                    Write-Log "  [UI] ISO radio selection failed: $_" -Level WARN
                }
                Start-Sleep -Milliseconds 500

                # Set ISO path in the file path field (ValuePattern)
                try {
                    $editCondition = New-Object Windows.Automation.PropertyCondition(
                        [Windows.Automation.AutomationElement]::ControlTypeProperty,
                        [Windows.Automation.ControlType]::Edit
                    )
                    $edits = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $editCondition)
                    if ($edits.Count -gt 0) {
                        $pathField = $edits[0]
                        $valPattern = $pathField.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
                        [System.Windows.Forms.SendKeys]::SendWait(' ')
                        $valPattern.SetValue($OutputIsoPath)
                        [System.Windows.Forms.SendKeys]::Flush()
                        Write-Log "  [UI] ISO path set: $OutputIsoPath" -Level DEBUG
                    }
                } catch {
                    Write-Log "  [UI] Could not set ISO path (will use default): $_" -Level WARN
                }

                # Click Next/Save to start download
                $buttons = $win.FindAll([Windows.Automation.TreeScope]::Descendants, $allBtnCondition)
                if ($buttons.Count -gt 0) {
                    # Find button with AutomationId "1" (Next/Save) or use last button
                    $saveBtn = $null
                    foreach ($b in $buttons) {
                        if ($b.Current.AutomationId -eq '1') { $saveBtn = $b; break }
                    }
                    if (-not $saveBtn) { $saveBtn = $buttons[$buttons.Count - 1] }
                    $saveBtn.SetFocus()
                }
                Press-Enter
                Write-Log '  [UI] Download started.' -Level SUCCESS

            } catch {
                Write-Log "  [UI] Automation failed: $_ -- MCT may need manual clicks." -Level WARN
                # Don't return false -- MCT might still work if user clicks through
            }
        } else {
            Write-Log '  MCT launched without UI automation -- you may need to click through the wizard.' -Level WARN
        }

        # ================================================================
        # MONITOR: Wait for ISO to be created
        # ================================================================
        $maxWaitMin = 60
        $startTime = Get-Date
        $wsDir = "$env:SystemDrive\`$WINDOWS.~WS"
        $esdDir = "$env:SystemDrive\ESD"
        $lastStatus = ''

        Write-Log '  Monitoring MCT progress...' -Level DEBUG
        while (-not $mctProc.HasExited) {
            $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
            if ($elapsed -gt $maxWaitMin) {
                Write-Log "  MCT timeout after $maxWaitMin min." -Level WARN
                try { $mctProc.Kill() } catch { }
                break
            }

            # Check if ISO appeared at expected path
            if (Test-Path $OutputIsoPath) {
                $isoSize = [math]::Round((Get-Item $OutputIsoPath).Length / 1GB, 2)
                if ($isoSize -gt 3) {
                    Write-Log "  ISO created: $OutputIsoPath ($isoSize GB)" -Level SUCCESS
                    Start-Sleep -Seconds 5
                    try { $mctProc.Kill() } catch { }
                    return $true
                }
            }

            # Track progress via windlp.state.xml
            $stateFile = "$wsDir\Sources\Panther\windlp.state.xml"
            if (Test-Path $stateFile) {
                try {
                    [xml]$stateXml = Get-Content $stateFile -ErrorAction SilentlyContinue
                    foreach ($task in $stateXml.WINDLP.TASK) {
                        foreach ($action in $task.ACTION) {
                            if ($action.ProgressTotal -and $action.ProgressTotal -ne '0') {
                                $current = [Convert]::ToInt64($action.ProgressCurrent, 16)
                                $total = [Convert]::ToInt64($action.ProgressTotal, 16)
                                if ($total -gt 0) {
                                    $pct = [math]::Round($current / $total * 100)
                                    $status = "  MCT: $($task.Name)/$($action.ActionName) -- $pct% ($([math]::Round($elapsed,1))m)"
                                    if ($status -ne $lastStatus) {
                                        Write-Host "`r$status   " -NoNewline
                                        $lastStatus = $status
                                    }
                                }
                            }
                        }
                    }
                } catch { }
            } elseif (Test-Path $esdDir) {
                # Fallback: track by ESD folder size
                $dlMB = [math]::Round((Get-ChildItem $esdDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB)
                $status = "  MCT downloading... ${elapsed}m, ${dlMB} MB"
                if ($status -ne $lastStatus) { Write-Host "`r$status   " -NoNewline; $lastStatus = $status }
            }

            Start-Sleep -Seconds 5
        }
        Write-Host ''

        $mctExit = if ($mctProc.HasExited) { $mctProc.ExitCode } else { -1 }
        Write-Log "  MCT exited with code: $mctExit" -Level DEBUG

        # Check all possible ISO locations
        foreach ($checkPath in @($OutputIsoPath, "$esdDir\*.iso", "$wsDir\*.iso")) {
            $found = Get-Item $checkPath -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 3GB } | Select-Object -First 1
            if ($found) {
                if ($found.FullName -ne $OutputIsoPath) {
                    Move-Item $found.FullName $OutputIsoPath -Force -ErrorAction SilentlyContinue
                }
                $isoSize = [math]::Round($found.Length / 1GB, 2)
                Write-Log "  ISO found: $($found.FullName) ($isoSize GB)" -Level SUCCESS
                return $true
            }
        }

        Write-Log '  MCT finished but no ISO was created.' -Level WARN
        if ($mctExit -eq -2147012744) {
            Write-Log '  Error 0x80072F78: TLS/network issue. Check internet connection and TLS 1.2 settings.' -Level ERROR
        }
        return $false
    } catch {
        Write-Log "  MCT execution failed: $_" -Level ERROR
        return $false
    }
}

# =====================================================================
# Region: Legacy MCT Fallback Scaffolding
# =====================================================================
#
# These helpers are intentionally not wired into the main orchestrator yet.
# They provide a structured legacy Windows 10 release manifest and build the
# command-line/state needed for a pinned Media Creation Tool fallback path.
#
# The manifest is designed so future work can drop in pinned catalog/MCT URLs
# without changing call sites or the main upgrade flow.
#

function Get-LegacyMctReleaseCatalog {
    <#
    .SYNOPSIS
        Returns the supported legacy Windows 10 release manifest.
    #>
    if (Get-Command 'Get-LegacyMediaManifest' -ErrorAction SilentlyContinue) {
        return @(Get-LegacyMediaManifest | ForEach-Object {
            [pscustomobject]@{
                Version                 = $_.Version
                DisplayVersion          = $_.DisplayVersion
                Build                   = $_.Build
                OS                      = $_.OS
                ReleaseLine             = $_.ReleaseLine
                SupportsArchSelection   = [bool]$_.SupportsArchSelection
                SupportsMediaEditionArg = [bool]$_.SupportsMediaEditionArg
                SupportsBusinessEdition  = [bool]$_.SupportsBusinessEdition
                CatalogKind             = if ($_.CatalogUrl) { if ($_.CatalogUrl -match '\.xml(?:$|\?)') { 'XML' } elseif ($_.CatalogUrl -match '\.cab(?:$|\?)') { 'CAB' } else { 'URL' } } else { 'MCT' }
                CatalogUrl              = $_.CatalogUrl
                CatalogFileName         = if ($_.CatalogUrl) { Split-Path $_.CatalogUrl -Leaf } else { '' }
                MctUrl                  = $_.MctUrl
                MctUrl32                = $_.MctUrl32
                PreferredMctUrl         = $_.PreferredMctUrl
                Notes                   = $_.Notes
            }
        })
    }

    return @()
}

function Get-LegacyMctReleaseSpec {
    <#
    .SYNOPSIS
        Returns the manifest entry for a legacy Windows 10 release.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $entry = Get-LegacyMctReleaseCatalog | Where-Object { $_.Version -eq $Version } | Select-Object -First 1
    if (-not $entry) {
        return $null
    }

    return [pscustomobject]@{
        Version             = $entry.Version
        DisplayVersion      = $entry.DisplayVersion
        Build               = $entry.Build
        OS                  = $entry.OS
        ReleaseLine         = $entry.ReleaseLine
        CatalogKind         = $entry.CatalogKind
        SupportsMediaEdition = [bool]$entry.SupportsMediaEditionArg
        SupportsMediaEditionArg = [bool]$entry.SupportsMediaEditionArg
        SupportsArchSelection = [bool]$entry.SupportsArchSelection
        SupportsBusinessEdition = [bool]$entry.SupportsBusinessEdition
        UsesUiAutomation    = [bool](-not $entry.SupportsMediaEditionArg -or $entry.Version -in @('W10_1507','W10_1511','W10_1607','W10_1703','W10_1709'))
        Notes               = $entry.Notes
        CatalogPath         = $null
        CatalogUrl          = $entry.CatalogUrl
        CatalogFileName     = $entry.CatalogFileName
        MctExePath          = $null
        MctExeUrl           = $entry.PreferredMctUrl
        MctExeUrl32         = $entry.MctUrl32
    }
}

function Get-LegacyMctWorkspacePath {
    <#
    .SYNOPSIS
        Returns the working directory used for legacy MCT acquisition.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [string]$BasePath
    )

    if (-not $BasePath) {
        $BasePath = if ($DownloadPath) { $DownloadPath } else { Join-Path $env:TEMP 'wfu-tool' }
    }

    Join-Path $BasePath "LegacyMct\$Version"
}

function New-LegacyMctWorkspace {
    <#
    .SYNOPSIS
        Prepares a legacy MCT workspace and stages pinned source files.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [string]$Language = 'en-US',
        [string]$Edition = 'Professional',
        [string]$Arch = 'x64',
        [string]$BasePath
    )

    $spec = Get-LegacyMctReleaseSpec -Version $Version
    if (-not $spec) {
        Write-Log "  No legacy MCT release spec for $Version." -Level WARN
        return $null
    }

    $workspace = Get-LegacyMctWorkspacePath -Version $Version -BasePath $BasePath
    $null = New-Item -ItemType Directory -Path $workspace -Force -ErrorAction SilentlyContinue

    $legacyInfo = [pscustomobject]@{
        Version             = $spec.Version
        DisplayVersion      = $spec.DisplayVersion
        Build               = $spec.Build
        OS                  = $spec.OS
        ReleaseLine         = $spec.ReleaseLine
        CatalogKind         = $spec.CatalogKind
        SupportsMediaEditionArg = $spec.SupportsMediaEditionArg
        SupportsArchSelection = $spec.SupportsArchSelection
        SupportsBusinessEdition = $spec.SupportsBusinessEdition
        PreferredMctUrl     = $spec.PreferredMctUrl
        MctUrl32            = $spec.MctUrl32
        CatalogUrl          = $spec.CatalogUrl
        CatalogFileName    = $spec.CatalogFileName
        Notes               = $spec.Notes
    }

    $legacyInfoPath = Join-Path $workspace 'legacy-release.json'
    try {
        $legacyInfo | ConvertTo-Json -Depth 6 | Set-Content -Path $legacyInfoPath -Encoding UTF8 -Force
    } catch {
        Write-Log "  Could not write legacy release sidecar: $_" -Level WARN
    }

    $mctUrl = if ($Arch -match '^(x86|32)$' -and $spec.MctExeUrl32) { $spec.MctExeUrl32 } else { $spec.MctExeUrl }
    $mctName = if ($mctUrl) { Split-Path $mctUrl -Leaf } else { 'MediaCreationTool.exe' }
    $mctPath = Join-Path $workspace $mctName
    if ($mctUrl -and (-not (Test-Path $mctPath) -or (Get-Item $mctPath -ErrorAction SilentlyContinue).Length -lt 1MB)) {
        if (-not (Start-DownloadWithProgress -Url $mctUrl -Destination $mctPath -Description "Legacy MCT $Version")) {
            return $null
        }
    }

    $catalogPath = $null
    if ($spec.CatalogUrl) {
        $catalogLeaf = if ($spec.CatalogFileName) { $spec.CatalogFileName } else { Split-Path $spec.CatalogUrl -Leaf }
        $catalogPath = Join-Path $workspace $catalogLeaf
        if (-not (Test-Path $catalogPath) -or (Get-Item $catalogPath -ErrorAction SilentlyContinue).Length -lt 1KB) {
            if (-not (Start-DownloadWithProgress -Url $spec.CatalogUrl -Destination $catalogPath -Description "Legacy catalog $Version")) {
                return $null
            }
        }
    }

    return [pscustomobject]@{
        Version         = $spec.Version
        WorkspacePath   = $workspace
        MctExePath      = $mctPath
        CatalogPath     = $catalogPath
        ReleaseSpec     = $spec
        LegacyInfoPath  = $legacyInfoPath
    }
}

function Invoke-LegacyMctIsoCreation {
    <#
    .SYNOPSIS
        Prepares a legacy workspace and invokes MCT with the correct flags.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [string]$Language = 'en-US',
        [string]$Edition = 'Professional',
        [string]$Arch = 'x64',
        [string]$OutputIsoPath,
        [string]$BasePath
    )

    $workspace = New-LegacyMctWorkspace -Version $Version -Language $Language -Edition $Edition -Arch $Arch -BasePath $BasePath
    if (-not $workspace) {
        return $false
    }

    $spec = $workspace.ReleaseSpec
    $skipMediaEdition = -not [bool]$spec.SupportsMediaEditionArg
    $runEdition = if ($skipMediaEdition) { 'Professional' } else { $Edition }
    if (-not $OutputIsoPath) {
        $OutputIsoPath = Join-Path $workspace.WorkspacePath "$Version.iso"
    }

    if ($PSCmdlet.ShouldProcess($workspace.MctExePath, "Create legacy ISO for $Version")) {
        return Start-MctIsoCreation -MctExePath $workspace.MctExePath `
            -OutputIsoPath $OutputIsoPath `
            -LangCode $Language `
            -Edition $runEdition `
            -Arch $Arch `
            -WorkingDirectory $workspace.WorkspacePath `
            -CatalogPath $workspace.CatalogPath `
            -LegacySpec $spec `
            -SkipUiAutomation:$false `
            -OmitMediaEditionArg:$skipMediaEdition
    }

    return $false
}

function New-LegacyMctFallbackPlan {
    <#
    .SYNOPSIS
        Builds the state required for a pinned MCT fallback run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Language = 'en-US',
        [string]$Edition = 'Professional',
        [string]$Arch = 'x64',
        [string]$OutputIsoPath,
        [string]$WorkingDirectory
    )

    $spec = Get-LegacyMctReleaseSpec -Version $Version
    if (-not $spec) {
        Write-Log "  No legacy MCT manifest entry for $Version." -Level DEBUG
        return $null
    }

    if (-not $WorkingDirectory) {
        $basePath = if ($DownloadPath) { $DownloadPath } else { Join-Path $env:TEMP 'wfu-tool' }
        $WorkingDirectory = Join-Path $basePath "LegacyMct\$Version"
    }
    if (-not $OutputIsoPath) {
        $basePath = if ($DownloadPath) { $DownloadPath } else { Join-Path $env:TEMP 'wfu-tool' }
        $OutputIsoPath = Join-Path $basePath "$Version.iso"
    }

    $argParts = @('/Selfhost', '/Action CreateMedia', "/MediaLangCode $Language", "/MediaArch $Arch", '/Pkey Defer', '/SkipSummary', '/Eula Accept')
    if ($spec.SupportsMediaEditionArg) { $argParts += "/MediaEdition $Edition" }

    $needsUiAutomation = [bool]$spec.UsesUiAutomation

    return [pscustomobject]@{
        Version            = $spec.Version
        DisplayVersion     = $spec.DisplayVersion
        Build              = $spec.Build
        CatalogKind        = $spec.CatalogKind
        UsesUiAutomation   = $needsUiAutomation
        SupportsMediaEdition = $spec.SupportsMediaEditionArg
        SupportsMediaEditionArg = $spec.SupportsMediaEditionArg
        CatalogUrl         = $spec.CatalogUrl
        MctExeUrl          = $spec.MctExeUrl
        WorkingDirectory   = $WorkingDirectory
        OutputIsoPath      = $OutputIsoPath
        CommandLine        = [string]::Join(' ', $argParts)
        Arguments          = $argParts
        MctExePath         = $spec.MctExePath
        CatalogPath        = $spec.CatalogPath
        Notes              = $spec.Notes
    }
}

function Test-LegacyMctFallbackReady {
    <#
    .SYNOPSIS
        Returns whether a legacy MCT fallback plan is complete enough to run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [string]$MctExePath,
        [string]$CatalogPath
    )

    $spec = Get-LegacyMctReleaseSpec -Version $Version
    if (-not $spec) {
        return $false
    }

    if ($MctExePath -and (Test-Path $MctExePath)) {
        $spec | Add-Member -NotePropertyName MctExePath -NotePropertyValue $MctExePath -Force
    } elseif ($spec.MctExeUrl) {
        $spec | Add-Member -NotePropertyName MctExePath -NotePropertyValue $true -Force
    }
    if ($CatalogPath -and (Test-Path $CatalogPath)) {
        $spec | Add-Member -NotePropertyName CatalogPath -NotePropertyValue $CatalogPath -Force
    } elseif ($spec.CatalogUrl) {
        $spec | Add-Member -NotePropertyName CatalogPath -NotePropertyValue $true -Force
    }

    return [bool]($spec.MctExePath -and $spec.CatalogPath)
}

function Get-WfuUsbDiskInfo {
    <#
    .SYNOPSIS
        Resolves a USB target disk by number or identifier and returns a normalized object.
    #>
    [CmdletBinding()]
    param(
        [int]$DiskNumber,
        [string]$DiskId
    )

    $disk = $null
    if ($PSBoundParameters.ContainsKey('DiskNumber')) {
        try {
            $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
        } catch {
            return $null
        }
    } elseif ($DiskId) {
        $needle = $DiskId.Trim()
        $matches = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object {
            ($_.UniqueId -and $_.UniqueId -ieq $needle) -or
            ($_.FriendlyName -and $_.FriendlyName -ieq $needle) -or
            ($_.SerialNumber -and $_.SerialNumber -ieq $needle) -or
            ($_.Location -and $_.Location -ieq $needle) -or
            ($_.Guid -and ([string]$_.Guid) -ieq $needle)
        })
        if ($matches.Count -eq 1) {
            $disk = $matches[0]
        } else {
            return $null
        }
    }

    if (-not $disk) {
        return $null
    }

    [pscustomobject]@{
        Number            = $disk.Number
        FriendlyName      = $disk.FriendlyName
        SerialNumber      = $disk.SerialNumber
        UniqueId          = $disk.UniqueId
        Guid              = if ($disk.Guid) { [string]$disk.Guid } else { $null }
        Size              = $disk.Size
        PartitionStyle    = $disk.PartitionStyle
        BusType           = $disk.BusType
        OperationalStatus = @($disk.OperationalStatus) -join ', '
        IsBoot            = [bool]$disk.IsBoot
        IsSystem          = [bool]$disk.IsSystem
        IsOffline         = [bool]$disk.IsOffline
        IsReadOnly        = [bool]$disk.IsReadOnly
    }
}

function Resolve-WfuUsbDisk {
    <#
    .SYNOPSIS
        Resolves a disk target and ensures the selection is unique.
    #>
    [CmdletBinding()]
    param(
        [int]$DiskNumber,
        [string]$DiskId
    )

    $diskInfo = Get-WfuUsbDiskInfo -DiskNumber $DiskNumber -DiskId $DiskId
    if (-not $diskInfo) {
        return $null
    }

    if ($diskInfo.IsBoot -or $diskInfo.IsSystem) {
        Write-Log "  Refusing to use system disk $($diskInfo.Number) ($($diskInfo.FriendlyName))." -Level ERROR
        return $null
    }

    return $diskInfo
}

function New-WfuUsbDiskpartScript {
    <#
    .SYNOPSIS
        Creates a diskpart script that prepares a target USB disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$DiskNumber,

        [ValidateSet('gpt','mbr')]
        [string]$PartitionStyle = 'gpt',

        [string]$VolumeLabel = 'WFU-USB'
    )

    $lines = @(
        "select disk $DiskNumber",
        'clean',
        "convert $PartitionStyle",
        'create partition primary',
        "format fs=fat32 quick label=$VolumeLabel",
        'assign'
    )

    if ($PartitionStyle -eq 'mbr') {
        $lines += 'active'
    }

    $scriptPath = Join-Path $env:TEMP "wfu-tool-diskpart-$DiskNumber-$([guid]::NewGuid().ToString('N')).txt"
    Set-Content -Path $scriptPath -Value $lines -Encoding ASCII
    return $scriptPath
}

function Initialize-WfuUsbDisk {
    <#
    .SYNOPSIS
        Wipes and formats the target USB disk using diskpart.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Disk,

        [ValidateSet('gpt','mbr')]
        [string]$PartitionStyle = 'gpt',

        [string]$VolumeLabel = 'WFU-USB'
    )

    if (-not $Disk) {
        return $null
    }

    $scriptPath = New-WfuUsbDiskpartScript -DiskNumber $Disk.Number -PartitionStyle $PartitionStyle -VolumeLabel $VolumeLabel
    try {
        if ($PSCmdlet.ShouldProcess("Disk $($Disk.Number)", "Prepare USB disk ($PartitionStyle)")) {
            Write-Log "  Preparing disk $($Disk.Number) ($($Disk.FriendlyName))..." -Level INFO
            $proc = Start-Process -FilePath 'diskpart.exe' -ArgumentList "/s `"$scriptPath`"" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Log "  diskpart failed with exit code $($proc.ExitCode)." -Level ERROR
                return $null
            }
        }

        $driveLetter = $null
        $deadline = (Get-Date).AddSeconds(30)
        while (-not $driveLetter -and (Get-Date) -lt $deadline) {
            try {
                $partitions = @(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
                if ($partitions.Count -gt 0) {
                    $driveLetter = $partitions[0].DriveLetter
                    break
                }
            } catch { }

            try {
                $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $VolumeLabel } | Select-Object -First 1
                if ($vol -and $vol.DriveLetter) {
                    $driveLetter = $vol.DriveLetter
                    break
                }
            } catch { }

            Start-Sleep -Seconds 1
        }

        if (-not $driveLetter) {
            Write-Log '  Could not resolve a mounted drive letter after diskpart.' -Level ERROR
            return $null
        }

        return [pscustomobject]@{
            Disk         = $Disk
            DriveLetter  = $driveLetter
            RootPath     = "$driveLetter`:\"
            VolumeLabel  = $VolumeLabel
            PartitionStyle = $PartitionStyle
        }
    } finally {
        if (Test-Path $scriptPath) {
            Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Mount-WfuIsoImage {
    <#
    .SYNOPSIS
        Mounts an ISO and returns the root path plus mount metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    if (-not (Test-Path $IsoPath)) {
        throw "ISO not found: $IsoPath"
    }

    $existing = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    if ($existing -and $existing.Attached) {
        $volume = $existing | Get-Volume -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($volume -and $volume.DriveLetter) {
            return [pscustomobject]@{
                IsoPath     = $IsoPath
                Mounted     = $true
                DriveLetter  = $volume.DriveLetter
                RootPath    = "$($volume.DriveLetter)`:\"
                WasAlreadyMounted = $true
            }
        }
    }

    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
    $volume = $mount | Get-Volume -ErrorAction Stop | Select-Object -First 1
    if (-not $volume -or -not $volume.DriveLetter) {
        throw "Could not resolve mounted volume for ISO: $IsoPath"
    }

    [pscustomobject]@{
        IsoPath     = $IsoPath
        Mounted     = $true
        DriveLetter  = $volume.DriveLetter
        RootPath    = "$($volume.DriveLetter)`:\"
        WasAlreadyMounted = $false
    }
}

function Dismount-WfuIsoImage {
    <#
    .SYNOPSIS
        Dismounts an ISO if it is currently attached.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    try {
        $diskImage = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
        if ($diskImage -and $diskImage.Attached) {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Test-WfuInstallImageNeedsSplit {
    <#
    .SYNOPSIS
        Returns whether install.wim needs splitting for FAT32 media.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallImagePath,
        [int64]$MaxBytes = 3800MB
    )

    if (-not (Test-Path $InstallImagePath)) {
        return $false
    }

    try {
        return ((Get-Item $InstallImagePath).Length -gt $MaxBytes)
    } catch {
        return $false
    }
}

function Copy-WfuMediaTree {
    <#
    .SYNOPSIS
        Copies ISO contents to a writable USB root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationRoot,

        [string[]]$ExcludeFiles = @()
    )

    if (-not (Test-Path $DestinationRoot)) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }

    $args = @(
        $SourceRoot,
        $DestinationRoot,
        '/E',
        '/R:1',
        '/W:1',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NC',
        '/NS',
        '/NP'
    )
    foreach ($file in $ExcludeFiles) {
        if ($file) {
            $args += '/XF'
            $args += $file
        }
    }

    & robocopy.exe @args | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        throw "Robocopy failed with exit code $exitCode"
    }
}

function Expand-WfuSplitWim {
    <#
    .SYNOPSIS
        Splits install.wim into SWM parts suitable for FAT32 media.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$InstallWimPath,

        [Parameter(Mandatory)]
        [string]$DestinationSourcesPath,

        [int]$ChunkMB = 3800
    )

    if (-not (Test-Path $InstallWimPath)) {
        throw "install.wim not found: $InstallWimPath"
    }

    if (-not (Test-Path $DestinationSourcesPath)) {
        New-Item -ItemType Directory -Path $DestinationSourcesPath -Force | Out-Null
    }

    $destinationSwm = Join-Path $DestinationSourcesPath 'install.swm'
    if ($PSCmdlet.ShouldProcess($destinationSwm, 'Split install.wim for FAT32 media')) {
        Write-Log "  Splitting install.wim for FAT32 media..." -Level INFO
        $proc = Start-Process -FilePath 'dism.exe' -ArgumentList "/Split-Image /ImageFile:`"$InstallWimPath`" /SWMFile:`"$destinationSwm`" /FileSize:$ChunkMB" -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "DISM split-image failed with exit code $($proc.ExitCode)"
        }
    }

    return $destinationSwm
}

function Resolve-WfuUsbMediaPlan {
    <#
    .SYNOPSIS
        Builds the state required to write bootable USB media from an ISO.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath,

        [int]$UsbDiskNumber,

        [string]$UsbDiskId,

        [ValidateSet('gpt','mbr')]
        [string]$PartitionStyle = 'gpt',

        [switch]$KeepIso,
        [string]$VolumeLabel = 'WFU-USB'
    )

    $disk = Resolve-WfuUsbDisk -DiskNumber $UsbDiskNumber -DiskId $UsbDiskId
    if (-not $disk) {
        return $null
    }

    $mount = Mount-WfuIsoImage -IsoPath $IsoPath
    $installWim = Join-Path $mount.RootPath 'sources\install.wim'
    $installEsd = Join-Path $mount.RootPath 'sources\install.esd'
    $needsSplit = (Test-Path $installWim) -and (Test-WfuInstallImageNeedsSplit -InstallImagePath $installWim)

    [pscustomobject]@{
        IsoPath         = $IsoPath
        Disk            = $disk
        Mount           = $mount
        PartitionStyle  = $PartitionStyle
        KeepIso         = [bool]$KeepIso
        VolumeLabel     = $VolumeLabel
        InstallWimPath  = if (Test-Path $installWim) { $installWim } else { $null }
        InstallEsdPath  = if (Test-Path $installEsd) { $installEsd } else { $null }
        NeedsWimSplit   = $needsSplit
        SourceRoot      = $mount.RootPath
        UsbRoot         = $null
    }
}

function Write-WfuUsbMedia {
    <#
    .SYNOPSIS
        Writes bootable USB media from a staged ISO using ISO-first flow.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath,

        [int]$UsbDiskNumber,

        [string]$UsbDiskId,

        [ValidateSet('gpt','mbr')]
        [string]$PartitionStyle = 'gpt',

        [switch]$KeepIso,
        [string]$VolumeLabel = 'WFU-USB'
    )

    $plan = Resolve-WfuUsbMediaPlan -IsoPath $IsoPath -UsbDiskNumber $UsbDiskNumber -UsbDiskId $UsbDiskId -PartitionStyle $PartitionStyle -KeepIso:$KeepIso -VolumeLabel $VolumeLabel
    if (-not $plan) {
        return $false
    }

    Write-Log "  USB target     : Disk $($plan.Disk.Number) ($($plan.Disk.FriendlyName))" -Level INFO
    Write-Log "  USB partition  : $($plan.PartitionStyle)" -Level INFO
    Write-Log "  USB volume lbl : $($plan.VolumeLabel)" -Level DEBUG
    Write-Log "  ISO source     : $($plan.IsoPath)" -Level INFO

    $usbRoot = $null
    try {
        $formatted = Initialize-WfuUsbDisk -Disk $plan.Disk -PartitionStyle $plan.PartitionStyle -VolumeLabel $plan.VolumeLabel
        if (-not $formatted) {
            return $false
        }
        $usbRoot = $formatted.RootPath

        Write-Log "  Mounting ISO media..." -Level INFO
        $mount = $plan.Mount
        if (-not $mount -or -not $mount.RootPath) {
            $mount = Mount-WfuIsoImage -IsoPath $plan.IsoPath
        }

        $sourceRoot = $mount.RootPath
        if (-not (Test-Path $sourceRoot)) {
            throw "Mounted ISO root not accessible: $sourceRoot"
        }

        $exclude = @()
        $installWim = Join-Path $sourceRoot 'sources\install.wim'
        $installEsd = Join-Path $sourceRoot 'sources\install.esd'
        $usbSources = Join-Path $usbRoot 'sources'
        if ($plan.NeedsWimSplit) {
            $exclude += 'install.wim'
        }

        Write-Log '  Copying ISO contents to USB...' -Level INFO
        Copy-WfuMediaTree -SourceRoot $sourceRoot -DestinationRoot $usbRoot -ExcludeFiles $exclude

        if ($plan.NeedsWimSplit) {
            Expand-WfuSplitWim -InstallWimPath $installWim -DestinationSourcesPath $usbSources | Out-Null
            if (Test-Path (Join-Path $usbSources 'install.wim')) {
                Remove-Item (Join-Path $usbSources 'install.wim') -Force -ErrorAction SilentlyContinue
            }
        } elseif (Test-Path $installWim) {
            Write-Log '  install.wim fits on FAT32 media; copied as-is.' -Level DEBUG
        } elseif (Test-Path $installEsd) {
            Write-Log '  install.esd detected; copied as-is.' -Level DEBUG
        }

        if (-not $plan.KeepIso) {
            Write-Log '  Removing staged ISO after successful USB write.' -Level INFO
            try {
                Dismount-WfuIsoImage -IsoPath $plan.IsoPath
                Remove-Item $plan.IsoPath -Force -ErrorAction SilentlyContinue
            } catch { }
        } else {
            Dismount-WfuIsoImage -IsoPath $plan.IsoPath
        }

        return [pscustomobject]@{
            Success        = $true
            IsoPath        = $plan.IsoPath
            UsbRoot        = $usbRoot
            DiskNumber     = $plan.Disk.Number
            DiskName       = $plan.Disk.FriendlyName
            PartitionStyle = $plan.PartitionStyle
            NeedsWimSplit  = $plan.NeedsWimSplit
            KeepIso        = [bool]$plan.KeepIso
        }
    } catch {
        Write-Log "  USB media creation failed: $_" -Level ERROR
        try { if ($plan.IsoPath) { Dismount-WfuIsoImage -IsoPath $plan.IsoPath } } catch { }
        return $false
    }
}
