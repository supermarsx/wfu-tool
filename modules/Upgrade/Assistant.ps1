function Install-SetupHostBypassHook {
    <#
    .SYNOPSIS
        Installs an IFEO (Image File Execution Options) debugger hook on SetupHost.exe.
        When the Installation Assistant launches SetupHost.exe for the compat check,
        our hook script runs first, applies bypasses, zeroes appraiserres.dll, and
        then launches SetupHost.exe with /Product Server trick.
    #>
    param([switch]$Remove)

    $ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SetupHost.exe'
    $scriptDir = "$env:SystemDrive\Scripts"
    $hookScript = Join-Path $scriptDir 'get11.cmd'

    if ($Remove) {
        try {
            if (Test-Path $ifeoBase) {
                Remove-Item $ifeoBase -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $hookScript -Force -ErrorAction SilentlyContinue
            Write-Log '  [IFEO] SetupHost.exe hook removed.' -Level DEBUG
        }
        catch { }
        return
    }

    Write-Log '  [IFEO] Installing SetupHost.exe bypass hook...'

    # Create the hook script that will intercept SetupHost.exe
    # When SetupHost.exe is launched by the Installation Assistant, Windows runs
    # our script instead (as the "debugger"). Our script applies all bypasses,
    # then launches the real SetupHost.exe with the right arguments.
    try {
        if (-not (Test-Path $scriptDir)) {
            New-Item -ItemType Directory -Path $scriptDir -Force -ErrorAction Stop | Out-Null
        }

        $hookContent = @'
@echo off
set "SOURCES=%SystemDrive%\$WINDOWS.~BT\Sources"
set "MEDIA=."

:: Only intercept the BT sources copy, not other SetupHost instances
if /i "%~f0" neq "%SystemDrive%\Scripts\get11.cmd" goto :eof
if not exist "%SOURCES%\SetupHost.exe" goto :eof

:: Apply registry bypasses
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /f /v DisableWUfBSafeguards /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\MoSetup" /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators" /f >nul 2>nul
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk" /f /v HwReqChkVars /t REG_MULTI_SZ /s , /d "SQ_SecureBootCapable=TRUE,SQ_SecureBootEnabled=TRUE,SQ_TpmVersion=2,SQ_RamMB=8192," >nul 2>nul

:: Create WindowsUpdateBox.exe hardlink if missing (needed for WU-based upgrades)
if not exist "%SOURCES%\WindowsUpdateBox.exe" mklink /h "%SOURCES%\WindowsUpdateBox.exe" "%SOURCES%\SetupHost.exe" >nul 2>nul

:: Zero-byte appraiserres.dll so compat check has nothing to evaluate
if exist "%SOURCES%\appraiserres.dll" cd.>"%SOURCES%\appraiserres.dll" 2>nul

:: Run the real SetupHost.exe with bypass options
set "OPT=/Compat IgnoreWarning /MigrateDrivers All /Telemetry Disable"
set CLI=%*
:: If appraiserres.dll is zeroed, use /Product Server trick
for %%A in ("%SOURCES%\appraiserres.dll") do if %%~zA equ 0 (set "TRICK=/Product Server ") else (set "TRICK=")
"%SOURCES%\WindowsUpdateBox.exe" %TRICK%%OPT% %CLI%
'@
        Set-Content -Path $hookScript -Value $hookContent -Encoding ASCII -Force -ErrorAction Stop
        Write-Log "  [IFEO] Hook script written to $hookScript" -Level DEBUG

        # Register the IFEO debugger -- only for $WINDOWS.~BT path (FilterFullPath)
        if (-not (Test-Path $ifeoBase)) {
            New-Item -Path $ifeoBase -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty $ifeoBase -Name 'UseFilter' -Value 1 -Type DWord -Force -ErrorAction Stop

        $filterKey = Join-Path $ifeoBase '0'
        if (-not (Test-Path $filterKey)) {
            New-Item -Path $filterKey -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty $filterKey -Name 'FilterFullPath' -Value "$env:SystemDrive\`$WINDOWS.~BT\Sources\SetupHost.exe" -Force -ErrorAction Stop
        Set-ItemProperty $filterKey -Name 'Debugger' -Value "$env:SystemDrive\Scripts\get11.cmd" -Force -ErrorAction Stop

        Write-Log '  [IFEO] SetupHost.exe hook registered.' -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "  [IFEO] Hook installation failed: $_" -Level WARN
        return $false
    }
}

function Test-UpgradeActuallyStarted {
    <#
    .SYNOPSIS
        Verifies that a Windows upgrade was actually initiated (not just the compat
        tool opening and closing). Checks for concrete evidence of upgrade activity.
    #>

    $evidence = @()

    # 1. $WINDOWS.~BT folder exists and has setup files
    $btPath = "$env:SystemDrive\`$WINDOWS.~BT"
    if (Test-Path $btPath) {
        $btSize = (Get-ChildItem $btPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($btSize -gt 100MB) {
            $evidence += "BT folder exists ($([math]::Round($btSize / 1MB)) MB)"
        }
    }

    # 2. SetupHost.exe or SetupPrep.exe is running
    $setupProcs = Get-Process -Name 'SetupHost', 'SetupPrep', 'WindowsUpdateBox' -ErrorAction SilentlyContinue
    if ($setupProcs) {
        $evidence += "Setup process running: $($setupProcs.Name -join ', ')"
    }

    # 3. Pending reboot registered by setup
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $evidence += 'WU reboot pending'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $evidence += 'CBS reboot pending'
    }

    # 4. setupact.log was recently written in Panther
    $pantherLog = "$env:SystemRoot\Panther\setupact.log"
    if (Test-Path $pantherLog) {
        $logAge = ((Get-Date) - (Get-Item $pantherLog).LastWriteTime).TotalMinutes
        if ($logAge -lt 10) {
            $evidence += "Panther log updated $([math]::Round($logAge, 1)) min ago"
        }
    }

    # 5. Windows Update download folder has new large files
    $dlPath = "$env:SystemDrive\`$WINDOWS.~BT\Sources"
    if (Test-Path $dlPath) {
        $recentFiles = Get-ChildItem $dlPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) -and $_.Length -gt 1MB }
        if ($recentFiles) {
            $evidence += "Recent files in BT\Sources: $($recentFiles.Count)"
        }
    }

    if ($evidence.Count -gt 0) {
        Write-Log "  Upgrade evidence found: $($evidence -join '; ')" -Level SUCCESS
        return $true
    }
    else {
        Write-Log '  No evidence of upgrade activity found.' -Level WARN
        return $false
    }
}

function Install-ViaInstallationAssistant {
    <#
    .SYNOPSIS
        Downloads and runs the Windows 11 Installation Assistant with full bypass:
        1. Installs IFEO hook to intercept SetupHost.exe compat check
        2. Applies compatibility registry bypasses
        3. Runs the assistant in silent mode
        4. Verifies an upgrade actually started (not just compat tool closing)
        5. Cleans up the IFEO hook afterward
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$Step)

    $assistantPath = Join-Path $DownloadPath 'Windows11InstallationAssistant.exe'
    $assistantUrl = 'https://go.microsoft.com/fwlink/?linkid=2171764'

    # Download the assistant if not present or suspiciously small
    $needsDownload = (-not (Test-Path $assistantPath)) -or ((Get-Item $assistantPath -ErrorAction SilentlyContinue).Length -lt 1MB)

    if ($needsDownload) {
        Write-Log '  Downloading Windows 11 Installation Assistant...'

        $downloaded = $false

        # Try Invoke-WebRequest
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $assistantUrl -OutFile $assistantPath -UseBasicParsing -ErrorAction Stop
            $ProgressPreference = 'Continue'
            $downloaded = $true
            Write-Log '  Download complete (Invoke-WebRequest).' -Level SUCCESS
        }
        catch {
            Write-Log "  Invoke-WebRequest failed: $_" -Level WARN
        }

        # Fallback: BITS
        if (-not $downloaded) {
            try {
                Start-BitsTransfer -Source $assistantUrl -Destination $assistantPath -ErrorAction Stop
                $downloaded = $true
                Write-Log '  Download complete (BITS).' -Level SUCCESS
            }
            catch {
                Write-Log "  BITS failed: $_" -Level WARN
            }
        }

        # Fallback: WebClient
        if (-not $downloaded) {
            try {
                (New-Object System.Net.WebClient).DownloadFile($assistantUrl, $assistantPath)
                $downloaded = $true
                Write-Log '  Download complete (WebClient).' -Level SUCCESS
            }
            catch {
                Write-Log "  WebClient failed: $_" -Level WARN
            }
        }

        # Fallback: curl
        if (-not $downloaded) {
            try {
                $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
                if (Test-Path $curlExe) {
                    & $curlExe -L -o $assistantPath $assistantUrl 2>$null
                    if ($LASTEXITCODE -eq 0) { $downloaded = $true; Write-Log '  Download complete (curl).' -Level SUCCESS }
                }
            }
            catch { }
        }

        if (-not $downloaded) {
            Write-Log '  All download methods failed for Installation Assistant.' -Level ERROR
            return $false
        }

        # Validate
        $fileSize = (Get-Item $assistantPath -ErrorAction SilentlyContinue).Length
        if ($fileSize -lt 1MB) {
            Write-Log "  Downloaded file is only $([math]::Round($fileSize/1KB)) KB -- likely corrupted." -Level ERROR
            Remove-Item $assistantPath -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Log "  File size: $([math]::Round($fileSize/1MB, 1)) MB" -Level DEBUG
    }

    if (-not (Test-Path $assistantPath)) {
        Write-Log '  Installation Assistant not found after download.' -Level ERROR
        return $false
    }

    # ================================================================
    # PRE-LAUNCH: Install the IFEO bypass hook
    # This intercepts SetupHost.exe when the assistant launches it,
    # zeroes appraiserres.dll, and applies the /Product Server trick.
    # Without this, the assistant shows a compat check window that
    # blocks on unsupported hardware (and exit code 0 on close = false positive).
    # ================================================================
    Write-Log '  Installing SetupHost.exe bypass hook (IFEO)...'
    $null = Install-SetupHostBypassHook

    # Also set DisableWUfBSafeguards so WU doesn't apply its own blocks
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableWUfBSafeguards' 1 'WUfB' | Out-Null

    # Record what existed before we start so we can verify afterward
    $btExistedBefore = Test-Path "$env:SystemDrive\`$WINDOWS.~BT\Sources\SetupHost.exe"

    # ================================================================
    # LAUNCH with process tree monitoring
    # The assistant spawns child processes and the parent exits immediately.
    # The real work happens in child processes:
    #   - Windows11InstallationAssistant.exe (UI/downloader)
    #   - SetupHost.exe (actual upgrade engine, intercepted by IFEO hook)
    #   - PCHealthCheck.exe / msedgewebview2.exe (compat UI -- must be killed)
    # We monitor ALL related processes, kill health-check ones, and wait
    # for setup to actually start downloading/installing.
    # ================================================================
    Write-Log '  Running Installation Assistant (silent mode with IFEO hook active)...'
    Write-Log '  Will monitor process tree and kill health check windows.' -Level DEBUG
    if ($PSCmdlet.ShouldProcess($assistantPath, 'Run Installation Assistant')) {
        try {
            # Snapshot processes before launch
            $beforePids = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

            # Launch -- parent may exit almost immediately, that's OK
            $proc = Start-Process -FilePath $assistantPath `
                -ArgumentList '/quiet /skipeula /auto upgrade /compat IgnoreWarning' `
                -PassThru -ErrorAction Stop

            if ($null -eq $proc) {
                Write-Log '  Installation Assistant process object is null.' -Level ERROR
                Install-SetupHostBypassHook -Remove
                return $false
            }

            $parentPid = $proc.Id
            Write-Log "  Launched PID $parentPid -- monitoring process tree..." -Level DEBUG

            # Processes to KILL on sight (health check / compat UI / upgrader nag)
            $killPatterns = @(
                'PCHealthCheck*',
                'msedgewebview2',
                'CompatTelRunner',
                'Windows10UpgraderApp',
                'Windows10Upgrader*',
                'WinREBootApp*'
            )

            # Processes that indicate the upgrade is working (DON'T kill these)
            $upgradePatterns = @(
                'SetupHost',
                'SetupPrep',
                'WindowsUpdateBox',
                'TiWorker',
                'TrustedInstaller'
            )

            # Processes that are assistant-related (track but don't kill)
            $assistantPatterns = @(
                'Windows11InstallationAssistant',
                'InstallAssistant'
            )

            $killed = @{}
            $maxWaitMin = 120
            $startTime = Get-Date
            $upgradeStarted = $false
            $assistantAlive = $true
            $noActivityCount = 0

            while ($assistantAlive -or $upgradeStarted) {
                # Check timeout
                $runtime = ((Get-Date) - $startTime).TotalMinutes
                if ($runtime -gt $maxWaitMin) {
                    Write-Log "  Timeout after $([math]::Round($runtime)) min." -Level WARN
                    break
                }

                # Scan for all related processes
                $allProcs = Get-Process -ErrorAction SilentlyContinue

                # Kill health check / compat UI processes
                foreach ($pattern in $killPatterns) {
                    $targets = $allProcs | Where-Object { $_.Name -like $pattern }
                    foreach ($p in $targets) {
                        if (-not $killed.ContainsKey($p.Id)) {
                            try {
                                $p.Kill()
                                $killed[$p.Id] = $p.Name
                                Write-Log "  [Kill] $($p.Name) (PID $($p.Id)) -- health check blocked" -Level WARN
                            }
                            catch { }
                        }
                    }
                }

                # Check if any assistant processes are still alive
                $assistantProcs = @()
                foreach ($pattern in $assistantPatterns) {
                    $assistantProcs += @($allProcs | Where-Object { $_.Name -like "*$pattern*" })
                }
                $assistantAlive = ($assistantProcs.Count -gt 0)

                # Check if upgrade-related processes are running
                $upgradeProcs = @()
                foreach ($pattern in $upgradePatterns) {
                    # Only count processes that started AFTER our launch
                    $upgradeProcs += @($allProcs | Where-Object {
                            $_.Name -like "*$pattern*" -and $beforePids -notcontains $_.Id
                        })
                }
                if ($upgradeProcs.Count -gt 0 -and -not $upgradeStarted) {
                    $upgradeStarted = $true
                    $procNames = ($upgradeProcs | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ', '
                    Write-Log "  Upgrade processes detected: $procNames" -Level SUCCESS
                }

                # If neither assistant nor upgrade processes are running, count inactivity
                if (-not $assistantAlive -and -not $upgradeStarted) {
                    $noActivityCount++
                    if ($noActivityCount -ge 5) {
                        # 10 seconds of no activity after assistant exited -- it's done
                        Write-Log '  Assistant exited and no upgrade processes detected.' -Level DEBUG
                        break
                    }
                }
                else {
                    $noActivityCount = 0
                }

                Start-Sleep -Seconds 2
            }

            if ($killed.Count -gt 0) {
                Write-Log "  Killed $($killed.Count) health check / compat process(es)." -Level WARN
            }

            # Determine exit code from whatever we can
            $exitCode = 0
            try {
                if ($proc.HasExited) { $exitCode = $proc.ExitCode }
            }
            catch { $exitCode = 0 }
            Write-Log "  Parent process exit code: $exitCode (parent may have spawned children)" -Level DEBUG

            # ================================================================
            # POST-LAUNCH: Verify upgrade actually started
            # Exit code 0 is NOT reliable -- the compat tool can close with 0
            # without starting any upgrade. We need to check for real evidence.
            # ================================================================

            # Give setup a moment to create files if it just started
            Start-Sleep -Seconds 5

            $upgradeStarted = Test-UpgradeActuallyStarted

            # Known exit codes
            switch ($exitCode) {
                { $_ -eq 0 -or $_ -eq 3010 -or $_ -eq 1641 } {
                    if ($upgradeStarted) {
                        Write-Log "  Installation Assistant: upgrade confirmed (code $exitCode)." -Level SUCCESS
                        Install-SetupHostBypassHook -Remove
                        return $true
                    }
                    else {
                        # Exit code 0 but no upgrade evidence -- compat tool was just dismissed
                        Write-Log "  Installation Assistant exited with code $exitCode but NO upgrade evidence found." -Level WARN
                        Write-Log '  The compatibility check window was likely closed without upgrading.' -Level WARN
                        Install-SetupHostBypassHook -Remove
                        return $false
                    }
                }
                default {
                    $knownCodes = @{
                        1603 = 'Fatal error during installation'
                        1618 = 'Another installation already in progress'
                        1602 = 'User cancelled'
                    }
                    $desc = $knownCodes[$exitCode]
                    if (-not $desc) { $desc = "Unknown error (0x{0:X8})" -f $exitCode }
                    Write-Log "  Installation Assistant failed: $desc (code $exitCode)" -Level WARN

                    # Even on error codes, check if upgrade somehow started
                    if ($upgradeStarted) {
                        Write-Log '  However, upgrade evidence WAS found -- treating as success.' -Level WARN
                        Install-SetupHostBypassHook -Remove
                        return $true
                    }

                    # Clean up the hook
                    Install-SetupHostBypassHook -Remove
                    return $false
                }
            }
        }
        catch {
            Write-Log "  Installation Assistant error: $_" -Level WARN
            Install-SetupHostBypassHook -Remove
            return $false
        }
    }

    return $false
}
