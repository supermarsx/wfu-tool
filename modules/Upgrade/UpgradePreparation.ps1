function Set-HardwareBypasses {
    <#
    .SYNOPSIS
        Injects all known registry bypasses so Windows Setup ignores TPM, Secure Boot,
        CPU, RAM, storage, and disk space requirements during feature updates.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log 'Injecting hardware requirement bypasses...'

    $totalBypasses = 0
    $failedBypasses = 0

    # ================================================================
    # PHASE 1: compatibility in-place upgrade bypass (documented compatibility bypass)
    # This is the proven method for in-place upgrades on unsupported HW.
    # It spoofs the appraiser results so setup.exe sees passing values.
    # ================================================================

    # 1a. Delete CompatMarkers -- cached appraiser block decisions
    try {
        $cmKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers'
        if (Test-Path $cmKey) {
            Remove-Item $cmKey -Recurse -Force -ErrorAction Stop
            Write-Log '  [Bypass] Deleted CompatMarkers' -Level SUCCESS
        }
        $totalBypasses++
    } catch { $failedBypasses++; Write-Log "  [Bypass] CompatMarkers delete failed: $_" -Level WARN }

    # 1b. Delete Shared -- cached shared appraiser data
    try {
        $sharedKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared'
        if (Test-Path $sharedKey) {
            Remove-Item $sharedKey -Recurse -Force -ErrorAction Stop
            Write-Log '  [Bypass] Deleted Shared' -Level SUCCESS
        }
        $totalBypasses++
    } catch { $failedBypasses++; Write-Log "  [Bypass] Shared delete failed: $_" -Level WARN }

    # 1c. Delete TargetVersionUpgradeExperienceIndicators -- safeguard holds
    try {
        $tvuKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators'
        if (Test-Path $tvuKey) {
            Remove-Item $tvuKey -Recurse -Force -ErrorAction Stop
            Write-Log '  [Bypass] Deleted TargetVersionUpgradeExperienceIndicators' -Level SUCCESS
        }
        $totalBypasses++
    } catch { $failedBypasses++; Write-Log "  [Bypass] TVUEI delete failed: $_" -Level WARN }

    # 1d. HwReqChkVars -- THE KEY BYPASS: spoof hardware check variables
    #     Instead of disabling the check, we feed it fake passing values.
    #     The appraiser reads these and thinks TPM 2.0, Secure Boot, 8GB RAM etc. are present.
    try {
        $hwReqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk'
        if (-not (Test-Path $hwReqKey)) {
            New-Item -Path $hwReqKey -Force -ErrorAction Stop | Out-Null
        }
        # REG_MULTI_SZ with spoofed passing values
        $spoofValues = @(
            'SQ_SecureBootCapable=TRUE'
            'SQ_SecureBootEnabled=TRUE'
            'SQ_TpmVersion=2'
            'SQ_RamMB=8192'
        )
        Set-ItemProperty -LiteralPath $hwReqKey -Name 'HwReqChkVars' -Value $spoofValues -Type MultiString -Force -ErrorAction Stop
        Write-Log '  [Bypass] HwReqChkVars = SecureBoot=TRUE, TPM=2, RAM=8192' -Level SUCCESS
        $totalBypasses++
    } catch {
        $failedBypasses++
        Write-Log "  [Bypass] HwReqChkVars failed: $_" -Level WARN
        # Fallback: try via reg.exe in case PowerShell can't write REG_MULTI_SZ properly
        try {
            & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk" /f /v HwReqChkVars /t REG_MULTI_SZ /s "," /d "SQ_SecureBootCapable=TRUE,SQ_SecureBootEnabled=TRUE,SQ_TpmVersion=2,SQ_RamMB=8192," 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log '  [Bypass] HwReqChkVars set via reg.exe fallback' -Level SUCCESS
                $failedBypasses--
                $totalBypasses++
            }
        } catch { }
    }

    # 1e. MoSetup AllowUpgradesWithUnsupportedTPMOrCPU
    if (Set-RegValue 'HKLM:\SYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1 'MoSetup') { $totalBypasses++ } else { $failedBypasses++ }

    # ================================================================
    # PHASE 2: Additional bypasses (belt and suspenders)
    # These cover edge cases the compatibility bypass set doesn't handle alone.
    # ================================================================

    # 2. MoSetup (SOFTWARE hive copy -- used by Installation Assistant)
    if (Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1 'MoSetup/SW') { $totalBypasses++ } else { $failedBypasses++ }

    # 3. LabConfig -- bypasses used by Windows Setup (setup.exe fresh/upgrade)
    $labConfigKey = 'HKLM:\SYSTEM\Setup\LabConfig'
    foreach ($bypass in @('BypassTPMCheck','BypassSecureBootCheck','BypassRAMCheck','BypassStorageCheck','BypassCPUCheck')) {
        if (Set-RegValue $labConfigKey $bypass 1 'LabConfig') { $totalBypasses++ } else { $failedBypasses++ }
    }

    # 4. Appraiser HwReqChk DWORD disable (older method, still helps on some builds)
    if (Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser' 'HwReqChk' 0 'Appraiser') { $totalBypasses++ } else { $failedBypasses++ }

    # 5. Feature update user preference
    try {
        $uxSettings = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        if (Test-Path $uxSettings) {
            Set-ItemProperty $uxSettings -Name 'IsExpedited' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Log '  [UXSettings] IsExpedited = 1' -Level SUCCESS
            $totalBypasses++
        }
    } catch { $failedBypasses++ }

    # 6. Product policy -- ensure edition allows upgrade
    if (Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade' 'AllowOSUpgrade' 1 'OSUpgrade') { $totalBypasses++ } else { $failedBypasses++ }

    # 7. Setup.exe /auto upgrade flyby
    if (Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup' 'SkipHWReqs' 1 'Setup') { $totalBypasses++ } else { $failedBypasses++ }

    # ================================================================
    # PHASE 3: Telemetry suppression
    # Block Microsoft telemetry/data collection during and after upgrade.
    # ================================================================

    # 8. Disable telemetry via registry policies
    $telemetryKeys = @(
        # AllowTelemetry = 0 (Security/off), 1 (Basic), 2 (Enhanced), 3 (Full)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Label = 'AllowTelemetry=0 (Off)' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'MaxTelemetryAllowed'; Value = 0; Label = 'MaxTelemetryAllowed=0' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableEnterpriseAuthProxy'; Value = 1; Label = 'DisableEnterpriseAuthProxy' },
        # Disable Customer Experience Improvement Program
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Value = 0; Label = 'CEIP=Off' },
        # Disable Application Telemetry
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = 0; Label = 'AppTelemetry=Off' },
        # Disable Inventory Collector
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Value = 1; Label = 'InventoryCollector=Off' },
        # Disable Steps Recorder (PSR)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableUAR'; Value = 1; Label = 'StepsRecorder=Off' },
        # Disable CompatTelRunner (the main telemetry executable)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisablePCA'; Value = 1; Label = 'CompatTelRunner=Off' },
        # Disable Windows Error Reporting
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1; Label = 'WER=Off' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Value = 1; Label = 'WER(User)=Off' },
        # Disable license telemetry
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform'; Name = 'NoGenTicket'; Value = 1; Label = 'LicenseTelemetry=Off' },
        # Disable Connected User Experiences (DiagTrack feeder)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableOneSettingsDownloads'; Value = 1; Label = 'OneSettings=Off' },
        # Disable advertising ID
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Value = 1; Label = 'AdvertisingID=Off' }
    )

    foreach ($tk in $telemetryKeys) {
        if (Set-RegValue $tk.Path $tk.Name $tk.Value "Telemetry/$($tk.Label)") { $totalBypasses++ } else { $failedBypasses++ }
    }

    # 9. Disable telemetry services (DiagTrack, dmwappushservice)
    $telemetryServices = @(
        @{ Name = 'DiagTrack';        Display = 'Connected User Experiences and Telemetry' },
        @{ Name = 'dmwappushservice'; Display = 'WAP Push Message Routing Service' }
    )
    foreach ($ts in $telemetryServices) {
        try {
            $svc = Get-Service $ts.Name -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -eq 'Running') {
                    Stop-ServiceSafe $ts.Name
                }
                Set-Service $ts.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "  [Telemetry] $($ts.Display) ($($ts.Name)) = Disabled" -Level SUCCESS
                $totalBypasses++
            }
        } catch {
            Write-Log "  [Telemetry] Could not disable $($ts.Name): $_" -Level WARN
            $failedBypasses++
        }
    }

    # 10. Disable telemetry scheduled tasks
    $telemetryTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    )
    $disabledTasks = 0
    foreach ($taskPath in $telemetryTasks) {
        try {
            $task = Get-ScheduledTask -TaskPath ($taskPath | Split-Path -Parent) -TaskName ($taskPath | Split-Path -Leaf) -ErrorAction SilentlyContinue
            if ($task -and $task.State -ne 'Disabled') {
                Disable-ScheduledTask -TaskPath ($taskPath | Split-Path -Parent) -TaskName ($taskPath | Split-Path -Leaf) -ErrorAction SilentlyContinue | Out-Null
                $disabledTasks++
            }
        } catch { }
    }
    if ($disabledTasks -gt 0) {
        Write-Log "  [Telemetry] Disabled $disabledTasks scheduled tasks" -Level SUCCESS
        $totalBypasses++
    }

    # 11. Block telemetry hosts via null routes (does not touch hosts file)
    $telemetryHosts = @(
        'vortex.data.microsoft.com',
        'vortex-win.data.microsoft.com',
        'telecommand.telemetry.microsoft.com',
        'telecommand.telemetry.microsoft.com.nsatc.net',
        'oca.telemetry.microsoft.com',
        'oca.telemetry.microsoft.com.nsatc.net',
        'sqm.telemetry.microsoft.com',
        'sqm.telemetry.microsoft.com.nsatc.net',
        'watson.telemetry.microsoft.com',
        'watson.telemetry.microsoft.com.nsatc.net',
        'redir.metaservices.microsoft.com',
        'choice.microsoft.com',
        'choice.microsoft.com.nsatc.net',
        'settings-win.data.microsoft.com',
        'vortex-sandbox.data.microsoft.com'
    )
    $blockedHosts = 0
    foreach ($h in $telemetryHosts) {
        try {
            # Resolve to check it exists, then add a null route
            $resolved = [System.Net.Dns]::GetHostAddresses($h) 2>$null
            if ($resolved) {
                foreach ($ip in $resolved) {
                    & route.exe add $ip.IPAddressToString 0.0.0.0 2>$null | Out-Null
                }
                $blockedHosts++
            }
        } catch { }
    }
    if ($blockedHosts -gt 0) {
        Write-Log "  [Telemetry] Null-routed $blockedHosts telemetry endpoints" -Level SUCCESS
        $totalBypasses++
    }

    # ================================================================
    # Summary
    # ================================================================

    if ($failedBypasses -eq 0) {
        Write-Log "All $totalBypasses bypasses + telemetry blocks applied successfully." -Level SUCCESS
    } else {
        Write-Log "$totalBypasses applied, $failedBypasses failed (upgrade may still work)." -Level WARN
    }
}

function Remove-UpgradeBlockers {
    <#
    .SYNOPSIS
        Removes known upgrade blockers like TargetReleaseVersion, WSUS locks,
        feature update deferrals, and stale Windows Update state.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log 'Removing known upgrade blockers...'
    $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    # 1. TargetReleaseVersion lock
    try {
        if ((Get-RegValue $wuKey 'TargetReleaseVersion') -eq 1) {
            $lockedTo = Get-RegValue $wuKey 'TargetReleaseVersionInfo'
            Write-Log "TargetReleaseVersion is LOCKED to '$lockedTo' -- removing lock." -Level WARN
            if ($PSCmdlet.ShouldProcess('TargetReleaseVersion registry', 'Remove')) {
                Remove-RegValue $wuKey 'TargetReleaseVersion'
                Remove-RegValue $wuKey 'TargetReleaseVersionInfo'
                Remove-RegValue $wuKey 'ProductVersion'
            }
        }
    } catch {
        Write-Log "TargetReleaseVersion check skipped: $_" -Level WARN
    }

    # 2. Safeguard hold IDs
    try {
        $shKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators'
        if (Test-Path $shKey) {
            Get-ChildItem $shKey -ErrorAction SilentlyContinue | ForEach-Object {
                $gatedVal = Get-RegValue $_.PSPath 'GatedBlockId'
                if ($gatedVal) {
                    Write-Log "Safeguard hold detected: $gatedVal under $($_.PSChildName)" -Level WARN
                }
                $redVal = Get-RegValue $_.PSPath 'RedReason'
                if ($redVal) {
                    Write-Log "  RedReason: $redVal" -Level WARN
                    Set-ItemProperty $_.PSPath -Name 'RedReason' -Value '' -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {
        Write-Log "Safeguard hold check skipped: $_" -Level WARN
    }

    # 3. Feature update deferral policies
    $deferKeys = @(
        @{ Path = $wuKey; Name = 'DeferFeatureUpdates' },
        @{ Path = $wuKey; Name = 'DeferFeatureUpdatesPeriodInDays' },
        @{ Path = $wuKey; Name = 'PauseFeatureUpdatesStartTime' },
        @{ Path = $wuKey; Name = 'DeferUpgrade' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'PauseFeatureUpdatesStartTime' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'PauseFeatureUpdatesEndTime' }
    )
    foreach ($dk in $deferKeys) {
        try {
            $val = Get-RegValue $dk.Path $dk.Name
            if ($null -ne $val) {
                Write-Log "Removing deferral: $($dk.Path)\$($dk.Name) = $val" -Level WARN
                Remove-RegValue $dk.Path $dk.Name
            }
        } catch { }
    }

    # 4. WSUS override -- temporarily disable if pointed at internal server
    try {
        $wsusServer = Get-RegValue $wuKey 'WUServer'
        if ($wsusServer) {
            Write-Log "System is pointed at WSUS: $wsusServer" -Level WARN
            $useWsus = Get-RegValue $wuKey 'UseWUServer'
            if ($useWsus -eq 1) {
                Write-Log "Temporarily disabling UseWUServer to allow direct Microsoft Update access." -Level WARN
                Set-RegValue $wuKey 'UseWUServer' 0 'WSUS'
                # Save original value so we can restore it
                Set-RegValue $Script:ResumeRegKey 'OriginalUseWUServer' 1 ''
            }
        }
    } catch { }

    # 5. Windows Update service state
    try {
        $wuService = Get-Service wuauserv -ErrorAction SilentlyContinue
        if ($wuService) {
            if ($wuService.StartType -eq 'Disabled') {
                Write-Log 'Windows Update service is disabled -- enabling it.' -Level WARN
                Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue
            }
            if ($wuService.Status -ne 'Running') {
                Start-Service wuauserv -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null
            }
        }
    } catch {
        Write-Log "Could not check/enable Windows Update service: $_" -Level WARN
    }

    # 6. SoftwareDistribution cleanup for stuck downloads
    try {
        $sdPath = "$env:SystemRoot\SoftwareDistribution\Download"
        $sdFiles = Get-ChildItem $sdPath -Recurse -File -ErrorAction SilentlyContinue
        $sdSize = ($sdFiles | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $sdSize) { $sdSize = 0 }
        $sdSizeGB = $sdSize / 1GB
        if ($sdSizeGB -gt 2) {
            Write-Log "SoftwareDistribution\Download is $([math]::Round($sdSizeGB,1)) GB -- cleaning stale downloads." -Level WARN
            Stop-ServiceSafe wuauserv
            Stop-ServiceSafe bits
            Remove-Item "$sdPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service bits -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null
            Start-Service wuauserv -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null
        }
    } catch { }

    # 7. Group Policy feature update blocks
    foreach ($bv in @('DisableOSUpgrade', 'SetDisableUXWUAccess')) {
        try {
            if ((Get-RegValue $wuKey $bv) -eq 1) {
                Write-Log "Group Policy block '$bv' is set -- removing." -Level WARN
                Remove-RegValue $wuKey $bv
            }
        } catch { }
    }

    # 8. AllowOSUpgrade
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade' 'AllowOSUpgrade' 1 '' | Out-Null

    # 9. Windows Edition check
    try {
        $edition = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
        if ($edition) {
            Write-Log "Windows Edition: $edition"
            if ($edition -match 'Enterprise|Education') {
                Write-Log 'Enterprise/Education -- ensure your organization allows feature updates.' -Level WARN
            }
        }
    } catch { }

    Write-Log 'Blocker removal complete.' -Level SUCCESS
}

function Get-CurrentWindowsVersion {
    <#
    .SYNOPSIS
        Reads current Windows build/version details from the registry.
    #>
    try {
        $ntVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $build = [int]$ntVer.CurrentBuildNumber
        $ubr   = [int]$ntVer.UBR

        # DisplayVersion exists on Win10 2004+ and all Win11 (e.g. "22H2", "25H2")
        $displayVersion = $ntVer.DisplayVersion
        # ReleaseId exists on older Win10 (e.g. "1809", "1903", "1909", "2004")
        # Microsoft stopped updating ReleaseId after 2004 (stuck at "2009")
        $releaseId = $ntVer.ReleaseId

        # Determine OS generation from build number (this is always reliable)
        $osName = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
        $osPrefix = if ($build -ge 22000) { '' } else { 'W10_' }

        # Determine the feature version using the ACTUAL registry value, not build guessing.
        # DisplayVersion is authoritative when present.
        $featureVersion = $null
        if ($displayVersion) {
            $featureVersion = $displayVersion  # e.g. "22H2", "25H2", "21H2"
        } elseif ($releaseId -and $releaseId -ne '2009') {
            # Old-style ReleaseId (1809, 1903, 1909, 2004)
            $featureVersion = $releaseId
        }

        # Build the version key (e.g. "25H2" for Win11, "W10_22H2" for Win10)
        if ($featureVersion) {
            $versionKey = "${osPrefix}${featureVersion}"
        } else {
            # Last resort: guess from build number (only for ancient builds without DisplayVersion)
            if     ($build -ge 22000) { $versionKey = '21H2' }       # Win11 RTM
            elseif ($build -ge 19041) { $versionKey = 'W10_2004' }   # generic 20H1 base
            elseif ($build -ge 18363) { $versionKey = 'W10_1909' }
            elseif ($build -ge 18362) { $versionKey = 'W10_1903' }
            elseif ($build -ge 17763) { $versionKey = 'W10_1809' }
            elseif ($build -ge 17134) { $versionKey = 'W10_1803' }
            elseif ($build -ge 16299) { $versionKey = 'W10_1709' }
            elseif ($build -ge 15063) { $versionKey = 'W10_1703' }
            elseif ($build -ge 14393) { $versionKey = 'W10_1607' }
            elseif ($build -ge 10240) { $versionKey = 'W10_1507' }
            else                      { $versionKey = 'Unknown' }
        }

        return @{
            Build          = $build
            UBR            = $ubr
            DisplayVersion = $displayVersion
            ReleaseId      = $releaseId
            VersionKey     = $versionKey
            FullBuild      = "$build.$ubr"
            OS             = $osName
        }
    } catch {
        Write-Log "CRITICAL: Cannot read Windows version from registry: $_" -Level ERROR
        return @{
            Build = 0; UBR = 0; DisplayVersion = 'Unknown'
            VersionKey = 'Unknown'; FullBuild = '0.0'
        }
    }
}

function Install-EnablementPackage {
    <#
    .SYNOPSIS
        Installs an enablement package (e.g., 22H2 -> 23H2) via Windows Update,
        DISM, or Windows Update scan trigger. Includes retry logic.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$Step)

    Write-Log "Attempting enablement package install: $($Step.Description)"

    # --- Method 1: Windows Update COM API ---
    Write-Log '[Method 1/3] Searching Windows Update for enablement package...'
    $wuResult = Invoke-WithRetry -Description 'Windows Update enablement search' -Action {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Software'")

        $enablementUpdate = $null
        foreach ($update in $searchResult.Updates) {
            $kbMatch = $false
            foreach ($kb in $update.KBArticleIDs) {
                if ($Step.KBArticle -and "KB$kb" -eq $Step.KBArticle) { $kbMatch = $true }
            }
            if ($kbMatch -or $update.Title -match 'enablement.*package' -or $update.Title -match $Step.To) {
                $enablementUpdate = $update
                break
            }
        }

        if (-not $enablementUpdate) { throw 'Enablement package not found in Windows Update catalog.' }

        Write-Log "  Found: $($enablementUpdate.Title)"

        $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToDownload.Add($enablementUpdate) | Out-Null
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToDownload
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -ne 2) { throw "Download failed with code $($downloadResult.ResultCode)." }
        Write-Log '  Download succeeded.' -Level SUCCESS

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToInstall.Add($enablementUpdate) | Out-Null
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        if ($installResult.ResultCode -ne 2) { throw "Install failed with code $($installResult.ResultCode)." }
        return $true
    }
    if ($wuResult -eq $true) {
        Write-Log 'Enablement package installed via Windows Update!' -Level SUCCESS
        return $true
    }

    # --- Method 2: DISM staged package ---
    Write-Log '[Method 2/3] Checking DISM for staged enablement packages...'
    try {
        $dismPackages = & dism.exe /Online /Get-Packages /Format:Table 2>&1
        $enablePkg = $dismPackages | Select-String -Pattern 'EnablementPackage' | Select-String -Pattern 'Staged|Install Pending'
        if ($enablePkg) {
            Write-Log "  Found staged enablement package in DISM -- applying..." -Level SUCCESS
            $pkgIdentity = ($enablePkg -split '\|')[0].Trim()
            Write-Host ''
            # No /Quiet so DISM shows its native progress bar
            $dismApply = Start-Process -FilePath 'dism.exe' `
                -ArgumentList '/Online', "/Add-Package /PackageName:`"$pkgIdentity`"", '/NoRestart' `
                -NoNewWindow -PassThru -Wait
            Write-Host ''
            $LASTEXITCODE = $dismApply.ExitCode
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                Write-Log 'DISM enablement package applied.' -Level SUCCESS
                return $true
            } else {
                Write-Log "DISM exited with code $LASTEXITCODE." -Level WARN
            }
        } else {
            Write-Log '  No staged enablement package found in DISM.' -Level WARN
        }
    } catch {
        Write-Log "DISM method failed: $_" -Level WARN
    }

    # --- Method 3: Trigger Windows Update scan ---
    Write-Log '[Method 3/3] Triggering Windows Update scan...'
    Start-WindowsUpdateScan
    Write-Log 'Windows Update scan triggered. The enablement package should appear in Settings > Windows Update.' -Level WARN
    Write-Log 'If it does not appear, download it from the Microsoft Update Catalog.' -Level WARN

    return $false
}

function Install-FeatureUpdate {
    <#
    .SYNOPSIS
        Performs a full feature update with 4 fallback methods:
        1. Windows Update COM API (with retry)
        2. Installation Assistant (with retry)
        3. Media Creation Tool ISO download
        4. Manual instructions + WU scan trigger
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$Step)

    Write-Log "Attempting feature update: $($Step.Description)"

    # Ensure download directory exists
    if (-not (Test-Path $DownloadPath)) {
        try { New-Item -ItemType Directory -Path $DownloadPath -Force -ErrorAction Stop | Out-Null }
        catch {
            Write-Log "Cannot create download directory $DownloadPath : $_" -Level ERROR
            # Fall back to temp
            $script:DownloadPath = Join-Path $env:TEMP 'wfu-tool'
            New-Item -ItemType Directory -Path $DownloadPath -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Using fallback directory: $DownloadPath" -Level WARN
        }
    }

    # --- Method 1: Direct ISO download + patched setup.exe (PREFERRED) ---
    Write-Log '[Method 1] Direct ISO upgrade (fastest, most reliable)...'
    $mctResult = Install-ViaIsoUpgrade -Step $Step
    if ($mctResult -is [array]) { $mctResult = $mctResult[-1] }
    if ($mctResult -eq $true) {
        Write-Log 'Feature update initiated via ISO!' -Level SUCCESS
        return $true
    }

    # ISO failed -- check if fallback is allowed
    if (-not $AllowFallback) {
        Write-Log '' -Level ERROR
        Write-Log '===============================================================' -Level ERROR
        Write-Log '  ISO DOWNLOAD FAILED -- OPERATION ABORTED' -Level ERROR
        Write-Log '===============================================================' -Level ERROR
        Write-Log '' -Level ERROR
        Write-Log '  The ISO method failed and fallback is DISABLED (default).' -Level ERROR
        Write-Log '  The upgrade will NOT proceed to avoid partial/inconsistent state.' -Level ERROR
        Write-Log '' -Level WARN
        Write-Log '  Options:' -Level WARN
        Write-Log '  1. Fix the network/TLS issue and re-run the script' -Level WARN
        Write-Log '  2. Manually download the ISO and place it at:' -Level WARN
        Write-Log "     $DownloadPath\Windows11.iso" -Level WARN
        Write-Log '  3. Re-run with -AllowFallback to try Installation Assistant and WU' -Level WARN
        Write-Log '' -Level WARN
        $null = Save-DiagnosticBundle -Reason "ISO download failed, fallback disabled"
        return $false
    }

    # --- Fallback methods (only when -AllowFallback is set) ---
    Write-Log '' -Level WARN
    Write-Log 'ISO method failed. -AllowFallback is enabled -- trying alternative methods...' -Level WARN
    Write-Log '' -Level WARN

    # --- Fallback: Installation Assistant with IFEO bypass hook ---
    if (-not $SkipAssistant) {
        Write-Log '[Fallback] Trying Installation Assistant (with SetupHost.exe hook)...'
        $assistantResult = Invoke-WithRetry -Description 'Installation Assistant' -Action {
            return Install-ViaInstallationAssistant -Step $Step
        }
        if ($assistantResult -is [array]) { $assistantResult = $assistantResult[-1] }
        if ($assistantResult -eq $true) { return $true }
    } else {
        Write-Log '  Installation Assistant: SKIPPED (disabled)' -Level DEBUG
    }

    # --- Fallback: Windows Update COM API ---
    if (-not $SkipWindowsUpdate) {
    Write-Log '[Fallback] Trying Windows Update...'
    $null = Repair-WindowsUpdateServices
    $wuResult = Invoke-WithRetry -Description 'Windows Update feature search' -Action {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0")

        $featureUpdate = $null
        foreach ($update in $searchResult.Updates) {
            if ($update.Title -match "Feature update to Windows 11.*$($Step.To)" -or
                $update.Title -match "Windows 11.*version $($Step.To)") {
                $featureUpdate = $update
                break
            }
        }
        if (-not $featureUpdate) {
            foreach ($update in $searchResult.Updates) {
                if ($update.Title -match 'Feature update to Windows 11') {
                    $featureUpdate = $update
                    break
                }
            }
        }

        if (-not $featureUpdate) { throw "Feature update to $($Step.To) not found in Windows Update." }

        Write-Log "  Found: $($featureUpdate.Title)"
        if (-not $featureUpdate.EulaAccepted) { $featureUpdate.AcceptEula() }

        $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToDownload.Add($featureUpdate) | Out-Null
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToDownload
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -ne 2) { throw "Download failed with code $($downloadResult.ResultCode)." }
        Write-Log '  Download complete.' -Level SUCCESS

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        $updatesToInstall.Add($featureUpdate) | Out-Null
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        switch ($installResult.ResultCode) {
            2 { return $true }
            3 { Write-Log '  Installed with errors -- check CBS logs.' -Level WARN; return $true }
            default { throw "Install failed with code $($installResult.ResultCode)." }
        }
    }
    if ($wuResult -eq $true) {
        Write-Log 'Feature update installed via Windows Update!' -Level SUCCESS
        return $true
    }
    } else {
        Write-Log '  Windows Update: SKIPPED (disabled)' -Level DEBUG
    }  # end SkipWindowsUpdate

    # --- Last resort: Trigger WU scan + manual instructions ---
    Write-Log 'All enabled methods failed -- triggering Windows Update scan...' -Level WARN
    $null = Start-WindowsUpdateScan

    # Capture diagnostics since all methods failed
    $null = Save-DiagnosticBundle -Reason "All 4 methods failed for upgrade to $($Step.To)"

    Write-Log '===============================================================' -Level WARN
    Write-Log '  ALL AUTOMATIC METHODS EXHAUSTED' -Level ERROR
    Write-Log "  Could not auto-upgrade to $($Step.To)." -Level ERROR
    Write-Log '' -Level WARN
    Write-Log '  Try these manual steps:' -Level WARN
    Write-Log '  1. Settings -> Windows Update -> Check for updates' -Level WARN
    Write-Log '  2. Download Update Assistant from:' -Level WARN
    Write-Log '     https://www.microsoft.com/software-download/windows11' -Level WARN
    Write-Log '  3. Use Media Creation Tool for in-place upgrade' -Level WARN
    Write-Log '  4. Check the diagnostics bundle for error details' -Level WARN
    Write-Log '' -Level WARN
    Write-Log '  After manual upgrade, re-run this script to continue.' -Level WARN
    Write-Log '===============================================================' -Level WARN

    return $false
}
