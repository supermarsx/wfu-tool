# Core helpers extracted from wfu-tool.ps1

function Get-ScriptScopedValue {
    param([string]$Name)

    $var = Get-Variable -Scope Script -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $var) {
        return $null
    }
    return $var.Value
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue } catch { }

    # If a phase spinner is active, move to next line first so log doesn't overwrite it
    if (Get-ScriptScopedValue 'PhaseStartTime') {
        Write-Host ''  # newline after the spinner's -NoNewline
    }

    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red; [void]$Script:ErrorLog.Add($entry) }
        'WARN' { Write-Host $entry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $entry -ForegroundColor Green }
        'DEBUG' { Write-Host $entry -ForegroundColor DarkGray }
        default { Write-Host $entry -ForegroundColor Cyan }
    }
}

function Write-Phase {
    <#
    .SYNOPSIS
        Starts a new task phase with visual indicator. When the next Write-Log call
        happens, the phase line gets a checkmark and elapsed time automatically.
        This gives the user a clear "what's happening now" + "how long did it take" view.
    #>
    param([string]$Message)

    # Close previous phase if any
    $phaseStart = Get-ScriptScopedValue 'PhaseStartTime'
    $phaseMessage = Get-ScriptScopedValue 'PhaseMessage'
    if ($phaseStart) {
        $secs = [math]::Round(((Get-Date) - $phaseStart).TotalSeconds)
        Write-Host "`r  $([char]0x2713) $phaseMessage [${secs}s]       " -ForegroundColor Green
    }

    # Start new phase
    $Script:PhaseStartTime = Get-Date
    $Script:PhaseMessage = $Message
    Write-Host "  - $Message ..." -NoNewline -ForegroundColor Cyan

    # Log it
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try { Add-Content -Path $LogPath -Value "[$timestamp] [PHASE] $Message" -ErrorAction SilentlyContinue } catch { }
}

function Complete-Phase {
    <#
    .SYNOPSIS
        Explicitly closes the current phase with success/fail and elapsed time.
        Call this after a major operation finishes. If not called, the next
        Write-Phase will auto-close it.
    #>
    param(
        [switch]$Fail,
        [string]$Message  # Optional override message
    )
    $phaseStart = Get-ScriptScopedValue 'PhaseStartTime'
    if (-not $phaseStart) { return }

    $secs = [math]::Round(((Get-Date) - $phaseStart).TotalSeconds)
    $msg = if ($Message) { $Message } else { (Get-ScriptScopedValue 'PhaseMessage') }

    if ($Fail) {
        Write-Host "`r  X $msg [${secs}s]       " -ForegroundColor Red
    }
    else {
        Write-Host "`r  $([char]0x2713) $msg [${secs}s]       " -ForegroundColor Green
    }

    $Script:PhaseStartTime = $null
    $Script:PhaseMessage = $null
}

function Get-RegValue {
    <#
    .SYNOPSIS
        Safely reads a single registry value. Returns $null on any failure.
    #>
    param([string]$Path, [string]$Name)
    try {
        if (-not (Test-Path $Path)) { return $null }
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($null -eq $item) { return $null }
        return $item.GetValue($Name, $null)
    }
    catch {
        return $null
    }
}

function Set-RegValue {
    <#
    .SYNOPSIS
        Safely creates a registry key (if needed) and sets a DWORD value.
        Returns $true on success, $false on failure.
    #>
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Label = ''
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
        if ($Label) { Write-Log "  [$Label] $Name = $Value" -Level SUCCESS }
        return $true
    }
    catch {
        $msg = "  Failed to set $Path\$Name"
        if ($Label) { $msg = "  [$Label] $msg" }
        Write-Log "$msg : $_" -Level WARN
        return $false
    }
}

function Remove-RegValue {
    <#
    .SYNOPSIS
        Safely removes a registry value. Silently succeeds if it doesn't exist.
    #>
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Stop-ServiceSafe {
    <#
    .SYNOPSIS
        Stops a Windows service with a timeout. If the service doesn't stop
        within the timeout, kills its process forcefully.
        Prevents the script from hanging on stuck services.
    #>
    param(
        [string]$Name,
        [int]$TimeoutSec = 15
    )

    try {
        $svc = Get-Service $Name -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') { return }

        # Try graceful stop
        $svc.Stop()
        try {
            $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($TimeoutSec))
        }
        catch {
            # Timeout -- force kill the process
            Write-Log "  Service '$Name' did not stop within ${TimeoutSec}s -- force killing." -Level WARN
            try {
                $wmi = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
                if ($wmi -and $wmi.ProcessId -gt 0) {
                    Stop-Process -Id $wmi.ProcessId -Force -ErrorAction SilentlyContinue
                    Write-Log "  Killed PID $($wmi.ProcessId) for $Name." -Level DEBUG
                }
            }
            catch {
                # Last resort: taskkill
                & taskkill.exe /F /FI "SERVICES eq $Name" 2>$null | Out-Null
            }
        }
    }
    catch {
        # Service may not exist or we may not have permission -- that's OK
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Runs a script block up to $MaxAttempts times with exponential backoff.
        Returns the script block's output on success, or $null on exhaustion.
    #>
    param(
        [scriptblock]$Action,
        [string]$Description = 'operation',
        [int]$MaxAttempts = $MaxRetries,
        [int]$BaseDelaySec = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $result = & $Action
            return $result
        }
        catch {
            $delay = $BaseDelaySec * [math]::Pow(2, $attempt - 1)
            if ($attempt -lt $MaxAttempts) {
                Write-Log "  $Description failed (attempt $attempt/$MaxAttempts): $_ -- retrying in ${delay}s..." -Level WARN
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Log "  $Description failed after $MaxAttempts attempts: $_" -Level ERROR
            }
        }
    }
    return $null
}

function Repair-WindowsUpdateServices {
    <#
    .SYNOPSIS
        Repairs Windows Update related services -- restarts them, resets stuck states,
        re-registers DLLs. Called when WU COM API fails.
    #>
    Write-Log 'Attempting Windows Update service recovery...'

    # Services that support Windows Update
    $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'TrustedInstaller')

    # Stop all WU-related services
    foreach ($svc in $services) {
        try {
            $s = Get-Service $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq 'Running') {
                Stop-ServiceSafe $svc
                Write-Log "  Stopped $svc" -Level DEBUG
            }
        }
        catch { }
    }

    # Rename SoftwareDistribution and catroot2 to force fresh state
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    $crPath = "$env:SystemRoot\System32\catroot2"
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    foreach ($folder in @($sdPath, $crPath)) {
        try {
            if (Test-Path $folder) {
                $backup = "${folder}.bak_${timestamp}"
                Rename-Item $folder $backup -Force -ErrorAction SilentlyContinue
                Write-Log "  Renamed $folder -> $backup" -Level DEBUG
            }
        }
        catch {
            Write-Log "  Could not rename $folder : $_" -Level WARN
        }
    }

    # Re-register critical Windows Update DLLs
    $dlls = @(
        'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll',
        'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll',
        'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll',
        'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
        'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll',
        'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll',
        'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll',
        'wuwebv.dll'
    )
    $regCount = 0
    foreach ($dll in $dlls) {
        try {
            $dllPath = Join-Path $env:SystemRoot "System32\$dll"
            if (Test-Path $dllPath) {
                & regsvr32.exe /s $dllPath 2>$null
                $regCount++
            }
        }
        catch { }
    }
    Write-Log "  Re-registered $regCount DLLs" -Level DEBUG

    # Reset Winsock and WinHTTP proxy
    try {
        & netsh.exe winsock reset 2>$null | Out-Null
        & netsh.exe winhttp reset proxy 2>$null | Out-Null
        Write-Log '  Winsock and WinHTTP proxy reset' -Level DEBUG
    }
    catch { }

    # Restart all services
    foreach ($svc in $services) {
        try {
            $s = Get-Service $svc -ErrorAction SilentlyContinue
            if ($s) {
                if ($s.StartType -eq 'Disabled') {
                    Set-Service $svc -StartupType Manual -ErrorAction SilentlyContinue
                }
                Start-Service $svc -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null
                Write-Log "  Started $svc" -Level DEBUG
            }
        }
        catch { }
    }

    Write-Log 'Windows Update service recovery complete.' -Level SUCCESS
}

function Test-NetworkReadiness {
    <#
    .SYNOPSIS
        Checks if the machine can reach Windows Update servers.
        Returns $true if reachable, $false if not.
    #>
    Write-Log 'Checking network connectivity to Windows Update...'

    $endpoints = @(
        @{ Host = 'download.windowsupdate.com'; Port = 443 },
        @{ Host = 'update.microsoft.com'; Port = 443 },
        @{ Host = 'go.microsoft.com'; Port = 443 },
        @{ Host = 'dl.delivery.mp.microsoft.com'; Port = 443 }
    )

    $reachable = 0
    foreach ($ep in $endpoints) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcp.ConnectAsync($ep.Host, $ep.Port)
            $completed = $connectTask.Wait(5000)
            if ($completed -and $tcp.Connected) {
                Write-Log "  OK: $($ep.Host):$($ep.Port)" -Level DEBUG
                $reachable++
            }
            else {
                Write-Log "  TIMEOUT: $($ep.Host):$($ep.Port)" -Level WARN
            }
            $tcp.Close()
        }
        catch {
            Write-Log "  FAIL: $($ep.Host):$($ep.Port) -- $_" -Level WARN
        }
    }

    if ($reachable -eq 0) {
        Write-Log 'No Windows Update endpoints reachable -- check network/firewall/proxy.' -Level ERROR
        return $false
    }
    elseif ($reachable -lt $endpoints.Count) {
        Write-Log "$reachable/$($endpoints.Count) endpoints reachable -- some may be blocked." -Level WARN
        return $true
    }
    else {
        Write-Log 'All Windows Update endpoints reachable.' -Level SUCCESS
        return $true
    }
}
