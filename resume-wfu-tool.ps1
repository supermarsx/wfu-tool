<#
.SYNOPSIS
    Resume wrapper -- launched by Scheduled Task after reboot.
    Opens a visible terminal, shows status, and re-runs the upgrade engine.
#>
param(
    [string]$ScriptRoot,
    [string]$TargetVersion,
    [string]$LogPath,
    [string]$DownloadPath,
    [switch]$NoReboot,
    [string]$CheckpointPath,
    [string]$SessionId,
    [switch]$ResumeFromCheckpoint
)

# Ensure we have a visible, scrollable, full-height window
$Host.UI.RawUI.WindowTitle = 'wfu-tool -- Resuming after reboot'
try {
    $buf = New-Object System.Management.Automation.Host.Size(120, 9999)
    $Host.UI.RawUI.BufferSize = $buf
    $win = New-Object System.Management.Automation.Host.Size(120, 50)
    $Host.UI.RawUI.WindowSize = $win
} catch {
    try { & mode.com con: cols=120 lines=50 } catch { }
}

function Write-Status {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host "  $Msg" -ForegroundColor $Color
}

function Get-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        if (-not (Test-Path $Path)) { return $null }
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($null -eq $item) { return $null }
        return $item.GetValue($Name, $null)
    } catch {
        return $null
    }
}

function Import-WfuAutomationHelpers {
    param([string]$BasePath)

    if (-not $BasePath) { return }
    $automationPath = Join-Path $BasePath 'modules\Upgrade\Automation.ps1'
    if (Test-Path $automationPath) {
        . $automationPath
    }
}

function Get-CheckpointPayload {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) {
        return $null
    }

    try {
        if (Get-Command Read-WfuCheckpoint -ErrorAction SilentlyContinue) {
            return Read-WfuCheckpoint -Path $Path
        }

        return (Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable)
    } catch {
        return $null
    }
}

function Resolve-ResumeState {
    param(
        [string]$ExplicitCheckpointPath,
        [string]$ExplicitSessionId,
        [switch]$ResumeRequested
    )

    $state = [ordered]@{
        CheckpointPath     = $null
        SessionId          = $null
        TargetVersion      = $null
        LogPath            = $null
        DownloadPath       = $null
        ConfigPath         = $null
        NoReboot           = $false
        ResumeFromCheckpoint = $false
        Payload            = $null
    }

    $storedCheckpointPath = $null
    $storedSessionId = $null
    $storedConfigPath = $null
    $storedTargetVersion = $null
    $storedLogPath = $null
    $storedDownloadPath = $null
    $storedResumeFlag = $null

    try {
        $regKey = 'HKLM:\SOFTWARE\wfu-tool'
        if (Test-Path $regKey) {
            $storedCheckpointPath = Get-RegistryValueSafe $regKey 'CheckpointPath'
            $storedSessionId = Get-RegistryValueSafe $regKey 'SessionId'
            $storedConfigPath = Get-RegistryValueSafe $regKey 'ConfigPath'
            $storedTargetVersion = Get-RegistryValueSafe $regKey 'TargetVersion'
            $storedLogPath = Get-RegistryValueSafe $regKey 'LogPath'
            $storedDownloadPath = Get-RegistryValueSafe $regKey 'DownloadPath'
            $storedResumeFlag = Get-RegistryValueSafe $regKey 'ResumeFromCheckpoint'
        }
    } catch { }

    $state.CheckpointPath = if ($ExplicitCheckpointPath) { $ExplicitCheckpointPath } elseif ($storedCheckpointPath) { $storedCheckpointPath } else { $null }
    $state.SessionId = if ($ExplicitSessionId) { $ExplicitSessionId } elseif ($storedSessionId) { $storedSessionId } else { $null }
    $state.ResumeFromCheckpoint = [bool]($ResumeRequested -or ($storedResumeFlag -eq 1) -or $state.CheckpointPath)

    $payload = Get-CheckpointPayload -Path $state.CheckpointPath
    if ($payload) {
        $state.Payload = $payload
        $state.ResumeFromCheckpoint = $true

        if ($payload.SessionId) { $state.SessionId = [string]$payload.SessionId }
        if ($payload.TargetVersion) { $state.TargetVersion = [string]$payload.TargetVersion }
        if ($payload.LogPath) { $state.LogPath = [string]$payload.LogPath }
        if ($payload.DownloadPath) { $state.DownloadPath = [string]$payload.DownloadPath }
        if ($payload.ConfigPath) { $state.ConfigPath = [string]$payload.ConfigPath }
        if ($payload.Options) {
            $options = $payload.Options
            if ($options.TargetVersion) { $state.TargetVersion = [string]$options.TargetVersion }
            if ($options.LogPath) { $state.LogPath = [string]$options.LogPath }
            if ($options.DownloadPath) { $state.DownloadPath = [string]$options.DownloadPath }
            if ($options.ConfigPath) { $state.ConfigPath = [string]$options.ConfigPath }
            if ($options.SessionId) { $state.SessionId = [string]$options.SessionId }
            if ($options.NoReboot) { $state.NoReboot = [bool]$options.NoReboot }
        }
        if ($payload.CurrentVersion) { $state.CurrentVersion = [string]$payload.CurrentVersion }
        if ($payload.NextStep) { $state.NextStep = [string]$payload.NextStep }
    } else {
        if ($storedTargetVersion) { $state.TargetVersion = [string]$storedTargetVersion }
        if ($storedLogPath) { $state.LogPath = [string]$storedLogPath }
        if ($storedDownloadPath) { $state.DownloadPath = [string]$storedDownloadPath }
        if ($storedConfigPath) { $state.ConfigPath = [string]$storedConfigPath }
    }

    if (-not $state.SessionId) { $state.SessionId = if ($ExplicitSessionId) { $ExplicitSessionId } else { $storedSessionId } }
    return $state
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   wfu-tool -- RESUMING' -ForegroundColor White
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host ''

# Wait a bit for services to stabilize after boot
Write-Status 'Waiting 15 seconds for system services to stabilize...' DarkGray
Start-Sleep -Seconds 15

# Validate paths
if ([string]::IsNullOrEmpty($ScriptRoot)) {
    # Try to find it from the registry
    try {
        $regKey = 'HKLM:\SOFTWARE\wfu-tool'
        if (Test-Path $regKey) {
            $savedPath = (Get-ItemProperty $regKey -ErrorAction SilentlyContinue).ScriptRoot
            if ($savedPath -and (Test-Path $savedPath)) { $ScriptRoot = $savedPath }
        }
    } catch { }
}

if ([string]::IsNullOrEmpty($ScriptRoot) -or -not (Test-Path $ScriptRoot)) {
    Write-Status "ERROR: Cannot find script directory: $ScriptRoot" Red
    Write-Status 'Please re-run launch-wfu-tool.bat manually.' Yellow
    Write-Host ''
    Write-Host '  Press any key to close...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

$resumeState = Resolve-ResumeState -ExplicitCheckpointPath $CheckpointPath -ExplicitSessionId $SessionId -ResumeRequested:$ResumeFromCheckpoint

$ScriptRoot = (Resolve-Path $ScriptRoot).Path
Import-WfuAutomationHelpers -BasePath $ScriptRoot

$upgradeScript = Join-Path $ScriptRoot 'wfu-tool.ps1'
if (-not (Test-Path $upgradeScript)) {
    Write-Status "ERROR: Cannot find wfu-tool.ps1 in $ScriptRoot" Red
    Write-Host ''
    Write-Host '  Press any key to close...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

# Show what we're resuming
Write-Status "Script root    : $ScriptRoot"
if ($resumeState.CheckpointPath) { Write-Status "Checkpoint     : $($resumeState.CheckpointPath)" }
if ($resumeState.SessionId) { Write-Status "Session id     : $($resumeState.SessionId)" }
if ($resumeState.TargetVersion) { Write-Status "Target version : $($resumeState.TargetVersion)" }
elseif ($TargetVersion) { Write-Status "Target version : $TargetVersion" }
if ($resumeState.LogPath) { Write-Status "Log file       : $($resumeState.LogPath)" }
elseif ($LogPath) { Write-Status "Log file       : $LogPath" }
Write-Status ''

# Build params
if (-not $TargetVersion -and $resumeState.TargetVersion) {
    $TargetVersion = $resumeState.TargetVersion
}
if (-not $LogPath -and $resumeState.LogPath) {
    $LogPath = $resumeState.LogPath
}
if (-not $DownloadPath -and $resumeState.DownloadPath) {
    $DownloadPath = $resumeState.DownloadPath
}

$params = @{
    Mode = 'Resume'
}
if ($TargetVersion)          { $params['TargetVersion'] = $TargetVersion }
if ($LogPath)                { $params['LogPath'] = $LogPath }
if ($DownloadPath)           { $params['DownloadPath'] = $DownloadPath }
if ($NoReboot -or $resumeState.NoReboot) { $params['NoReboot'] = $true }
if ($resumeState.CheckpointPath) { $params['CheckpointPath'] = $resumeState.CheckpointPath }
if ($resumeState.SessionId)  { $params['SessionId'] = $resumeState.SessionId }
if ($resumeState.ResumeFromCheckpoint) { $params['ResumeFromCheckpoint'] = $true }
if ($resumeState.ConfigPath) { $params['ConfigPath'] = $resumeState.ConfigPath }

Write-Status 'Launching upgrade engine...' Green
Write-Host ''

# Run the upgrade engine
try {
    Set-ExecutionPolicy -Scope Process -Force Bypass -ErrorAction SilentlyContinue
    & $upgradeScript @params
} catch {
    Write-Status "ERROR: $($_.Exception.Message)" Red
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '   Resume complete. Check the log for details.' -ForegroundColor White
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Press any key to close...' -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
