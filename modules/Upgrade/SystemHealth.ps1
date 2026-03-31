# =====================================================================
# Region: Diagnostic Capture
# =====================================================================

function Save-DiagnosticBundle {
    <#
    .SYNOPSIS
        Captures CBS logs, DISM health, update history, and error summary
        into a diagnostic folder for troubleshooting failed upgrades.
    #>
    param([string]$Reason = 'Upgrade failure')

    $diagDir = Join-Path $DownloadPath "Diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    try {
        New-Item -ItemType Directory -Path $diagDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log "Could not create diagnostics folder: $_" -Level WARN
        return
    }

    Write-Log "Capturing diagnostic bundle to $diagDir ..."

    # 1. Copy CBS log
    try {
        $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
        if (Test-Path $cbsLog) {
            Copy-Item $cbsLog (Join-Path $diagDir 'CBS.log') -Force -ErrorAction SilentlyContinue
            Write-Log '  Captured CBS.log' -Level DEBUG
        }
    } catch { }

    # 2. Copy DISM log
    try {
        $dismLog = "$env:SystemRoot\Logs\DISM\dism.log"
        if (Test-Path $dismLog) {
            Copy-Item $dismLog (Join-Path $diagDir 'DISM.log') -Force -ErrorAction SilentlyContinue
            Write-Log '  Captured DISM.log' -Level DEBUG
        }
    } catch { }

    # 3. Copy SetupErr/SetupAct from Panther
    try {
        $pantherDir = "$env:SystemRoot\Panther"
        if (Test-Path $pantherDir) {
            foreach ($f in @('setupact.log','setuperr.log','setupapi.dev.log')) {
                $src = Join-Path $pantherDir $f
                if (Test-Path $src) {
                    Copy-Item $src (Join-Path $diagDir $f) -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Log '  Captured Panther logs' -Level DEBUG
        }
    } catch { }

    # 4. DISM component store health check
    try {
        $healthFile = Join-Path $diagDir 'DISM_Health.txt'
        & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-File $healthFile -Encoding ascii -ErrorAction SilentlyContinue
        Write-Log '  Captured DISM health check' -Level DEBUG
    } catch { }

    # 5. Windows Update log (PS 5.1+ can generate it) -- suppress console spam
    try {
        $wuLogFile = Join-Path $diagDir 'WindowsUpdate.log'
        # Run in a hidden child process -- Get-WindowsUpdateLog writes directly to console host
        $wuProc = Start-Process powershell.exe -ArgumentList "-NoProfile -Command `"Get-WindowsUpdateLog -LogPath '$wuLogFile'`"" `
            -WindowStyle Hidden -PassThru -Wait -ErrorAction SilentlyContinue
        Write-Log '  Captured WindowsUpdate.log' -Level DEBUG
    } catch { }

    # 6. Installed updates list
    try {
        $updatesFile = Join-Path $diagDir 'InstalledUpdates.txt'
        Get-HotFix -ErrorAction SilentlyContinue |
            Sort-Object InstalledOn -Descending |
            Format-Table -AutoSize |
            Out-File $updatesFile -Encoding ascii -ErrorAction SilentlyContinue
        Write-Log '  Captured installed updates list' -Level DEBUG
    } catch { }

    # 7. System info snapshot
    try {
        $sysFile = Join-Path $diagDir 'SystemInfo.txt'
        $sysInfo = @(
            "Computer: $env:COMPUTERNAME"
            "OS: $((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption)"
            "Build: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber)"
            "UBR: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR)"
            "Edition: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID)"
            "RAM: $([math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)) GB"
            "Free Disk: $([math]::Round((Get-PSDrive ($env:SystemDrive[0]) -ErrorAction SilentlyContinue).Free / 1GB, 1)) GB"
            ""
            "Reason: $Reason"
            "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )
        $sysInfo | Out-File $sysFile -Encoding ascii -ErrorAction SilentlyContinue
        Write-Log '  Captured system info' -Level DEBUG
    } catch { }

    # 8. Error summary
    if ($Script:ErrorLog.Count -gt 0) {
        try {
            $errFile = Join-Path $diagDir 'ErrorSummary.txt'
            $Script:ErrorLog | Out-File $errFile -Encoding ascii -ErrorAction SilentlyContinue
            Write-Log "  Captured $($Script:ErrorLog.Count) error(s)" -Level DEBUG
        } catch { }
    }

    # 9. Copy our own log
    try {
        if (Test-Path $LogPath) {
            Copy-Item $LogPath (Join-Path $diagDir 'wfu-tool.log') -Force -ErrorAction SilentlyContinue
        }
    } catch { }

    Write-Log "Diagnostic bundle saved to: $diagDir" -Level WARN
    Write-Log "Share this folder when reporting issues." -Level WARN
}

# =====================================================================
# Region: Component Store Repair
# =====================================================================

function Repair-ComponentStore {
    <#
    .SYNOPSIS
        Runs DISM and SFC to repair the component store before attempting upgrades.
        Returns $true if repairs succeeded or were not needed.
    #>
    Write-Log 'Checking component store health...'

    # DISM RestoreHealth -- stream live to console so user sees progress %
    try {
        Write-Log '  Running DISM /RestoreHealth (this may take several minutes)...'
        Write-Host ''
        # Run without capturing so DISM's native progress bar renders in the console
        $dismProc = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth' `
            -NoNewWindow -PassThru -Wait
        Write-Host ''
        $dismExit = $dismProc.ExitCode
        if ($dismExit -eq 0) {
            Write-Log '  DISM: Component store is healthy.' -Level SUCCESS
        } elseif ($dismExit -eq 87) {
            Write-Log '  DISM: Unknown option -- skipping (older Windows version).' -Level WARN
        } else {
            Write-Log "  DISM exited with code $dismExit." -Level WARN
        }
    } catch {
        Write-Log "  DISM failed: $_" -Level WARN
    }

    # SFC /scannow -- stream live to console so user sees progress %
    try {
        Write-Log '  Running SFC /scannow...'
        Write-Host ''
        $sfcProc = Start-Process -FilePath 'sfc.exe' `
            -ArgumentList '/scannow' `
            -NoNewWindow -PassThru -Wait
        Write-Host ''
        $sfcExit = $sfcProc.ExitCode
        if ($sfcExit -eq 0) {
            Write-Log '  SFC: No integrity violations found.' -Level SUCCESS
        } else {
            Write-Log "  SFC exited with code $sfcExit." -Level WARN
        }
    } catch {
        Write-Log "  SFC failed: $_" -Level WARN
    }

    return $true
}

# =====================================================================
# Region: Pending Reboot Detection
# =====================================================================

function Test-PendingReboot {
    <#
    .SYNOPSIS
        Checks multiple sources for pending reboots.
        Returns $true if a reboot is pending.
    #>
    $pending = $false
    $reasons = @()

    # CBS RebootPending
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $pending = $true
        $reasons += 'CBS RebootPending'
    }

    # Windows Update RebootRequired
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $pending = $true
        $reasons += 'Windows Update RebootRequired'
    }

    # Pending file rename operations
    $pfro = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    if ($pfro) {
        $pending = $true
        $reasons += 'PendingFileRenameOperations'
    }

    # Computer rename pending
    $activeName = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' 'ComputerName'
    $pendingName = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName'
    if ($activeName -and $pendingName -and $activeName -ne $pendingName) {
        $pending = $true
        $reasons += 'Computer rename pending'
    }

    if ($pending) {
        Write-Log "Pending reboot detected: $($reasons -join ', ')" -Level WARN
    }
    return $pending
}

# =====================================================================
# Region: Disk Space Check
# =====================================================================

function Test-DiskSpace {
    <#
    .SYNOPSIS
        Verifies enough free disk space for the upgrade. Attempts cleanup if low.
        Returns $true if space is sufficient (or was freed), $false if critically low.
    #>
    param([int]$RequiredGB = 15)

    try {
        $drive = Get-PSDrive ($env:SystemDrive[0]) -ErrorAction SilentlyContinue
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        Write-Log "Disk space: $freeGB GB free on $env:SystemDrive (need $RequiredGB GB)"

        if ($freeGB -ge $RequiredGB) {
            return $true
        }

        Write-Log "Low disk space -- attempting cleanup..." -Level WARN

        # Run Disk Cleanup silently (sageset 65535 = all options)
        try {
            # Set all cleanup options
            $cleanupKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            if (Test-Path $cleanupKey) {
                Get-ChildItem $cleanupKey -ErrorAction SilentlyContinue | ForEach-Object {
                    Set-ItemProperty $_.PSPath -Name 'StateFlags0099' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }
            & cleanmgr.exe /sagerun:99 2>$null | Out-Null
            Write-Log '  Disk Cleanup completed.' -Level DEBUG
        } catch { }

        # Clear Windows temp
        try {
            Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log '  Temp folders cleaned.' -Level DEBUG
        } catch { }

        # Clear SoftwareDistribution downloads
        try {
            Stop-ServiceSafe wuauserv
            Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null
            Write-Log '  SoftwareDistribution\Download cleaned.' -Level DEBUG
        } catch { }

        # Re-check
        $drive = Get-PSDrive ($env:SystemDrive[0]) -ErrorAction SilentlyContinue
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        Write-Log "Disk space after cleanup: $freeGB GB free"

        if ($freeGB -lt $RequiredGB) {
            Write-Log "Still only $freeGB GB free -- upgrade may fail. Need at least $RequiredGB GB." -Level ERROR
            return $false
        }

        Write-Log "Disk space recovered -- $freeGB GB available." -Level SUCCESS
        return $true
    } catch {
        Write-Log "Could not check disk space: $_" -Level WARN
        return $true  # Don't block on check failure
    }
}
