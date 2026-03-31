<#
.SYNOPSIS
    wfu-tool -- One-Click Sequential Upgrade
.DESCRIPTION
    Detects the current Windows feature release and upgrades sequentially through
    supported Windows 10 and Windows 11 releases until the latest supported release:
        W10_1507 -> W10_1511 -> W10_1607 -> W10_1703 -> W10_1709 -> W10_1803 ->
        W10_1809 -> W10_1903 -> W10_1909 -> W10_2004 -> W10_20H2 -> W10_21H1 ->
        W10_21H2 -> W10_22H2 -> 21H2 -> 22H2 -> 23H2 -> 24H2 -> 25H2

    Supports enablement packages (minor jumps) and full feature updates (major jumps).
    Handles safeguard holds, TargetReleaseVersion locks, hardware requirement bypasses,
    and automatic reboot scheduling with resume-after-reboot capability.

    Automatically injects registry bypasses for TPM 2.0, Secure Boot, CPU, RAM, storage,
    and disk space checks so upgrades proceed on any hardware.

    Includes extensive error handling with retry logic, fallback methods, service recovery,
    network diagnostics, and CBS log capture for troubleshooting.

.PARAMETER TargetVersion
    Stop upgrading at this version instead of going all the way to the latest.
    Valid values: W10_1507 through W10_22H2, 21H2, 22H2, 23H2, 24H2, 25H2

.PARAMETER NoReboot
    Suppress automatic reboot after each upgrade step. The script will remind you
    to reboot manually and re-run.

.PARAMETER LogPath
    Path to the log file. Defaults to .\wfu-tool.log

.PARAMETER DownloadPath
    Directory for downloaded update packages. Defaults to C:\wfu-tool

.PARAMETER ForceOnlineUpdate
    Always use Windows Update (online) even when an offline enablement package
    would normally be used.

.PARAMETER MaxRetries
    Maximum number of retries for each upgrade method before moving to the next
    fallback. Defaults to 2.

.EXAMPLE
    .\wfu-tool.ps1
    # Upgrades from current version to the latest, step by step.

.EXAMPLE
    .\wfu-tool.ps1 -TargetVersion 24H2 -NoReboot
    # Upgrades up to 24H2 and suppresses automatic reboot.

.NOTES
    Author  : supermarsx
    Version : 3.0
    Tested  : Windows 10 1507 through 22H2, Windows 11 21H2 through 25H2
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Alias('?')]
    [switch]$Help,

    [string]$ConfigPath,

    [ValidateSet('Interactive','Headless','Resume','CreateUsb','IsoDownload','UsbFromIso','AutomatedUpgrade')]
    [string]$Mode,

    [switch]$Interactive,
    [switch]$Headless,

    [string]$TargetVersion = '25H2',

    [switch]$NoReboot,

    [string]$LogPath = (Join-Path $PSScriptRoot 'wfu-tool.log'),
    [string]$DownloadPath = 'C:\wfu-tool',

    [switch]$ForceOnlineUpdate,

    [int]$MaxRetries = 2,

    # Direct ISO upgrade -- skip intermediate versions, jump straight to target
    [switch]$DirectIso,

    [switch]$CreateUsb,
    [int]$UsbDiskNumber,
    [string]$UsbDiskId,
    [switch]$KeepIso,
    [ValidateSet('gpt','mbr')]
    [string]$UsbPartitionStyle = 'gpt',
    [string]$PreferredSource,
    [string]$ForceSource,
    [switch]$AllowDeadSources,
    [string]$CheckpointPath,
    [string]$SessionId,
    [switch]$ResumeFromCheckpoint,

    # Allow fallback to sequential/assistant methods if ISO download fails.
    # Default is OFF -- if ISO fails, the whole operation fails.
    # User must explicitly enable fallback.
    [switch]$AllowFallback,

    # Step toggles -- allow skipping individual pre-flight phases
    [switch]$SkipBypasses,
    [switch]$SkipBlockerRemoval,
    [switch]$SkipTelemetry,
    [switch]$SkipRepair,
    [switch]$SkipCumulativeUpdates,
    [switch]$SkipNetworkCheck,
    [switch]$SkipDiskCheck,

    # Download/upgrade method toggles -- each method can be individually disabled
    [switch]$SkipDirectEsd,            # Skip direct WU/direct release ESD download (all versions, permanent CDN)
    [switch]$SkipEsd,            # Skip ESD catalog download (22H2/23H2 only)
    [switch]$SkipFido,           # Skip Fido direct ISO API
    [switch]$SkipMct,            # Skip Media Creation Tool
    [switch]$SkipAssistant,      # Skip Installation Assistant
    [switch]$SkipWindowsUpdate   # Skip Windows Update COM API
)

function Show-WfuCliHelp {
    Write-Host ''
    Write-Host 'wfu-tool' -ForegroundColor Cyan
    Write-Host 'Usage: .\wfu-tool.ps1 [options]' -ForegroundColor White
    Write-Host ''
    Write-Host 'Common options:' -ForegroundColor Cyan
    Write-Host '  -Help                         Show this help text'
    Write-Host '  -Mode <Interactive|Headless|Resume|CreateUsb|IsoDownload|UsbFromIso|AutomatedUpgrade>'
    Write-Host '  -TargetVersion <version>      Example: W10_22H2, 24H2, 25H2'
    Write-Host '  -ConfigPath <path>            Load options from an INI file'
    Write-Host '  -CheckpointPath <path>        Use an explicit checkpoint file'
    Write-Host '  -ResumeFromCheckpoint         Resume from saved checkpoint state'
    Write-Host ''
    Write-Host 'Upgrade behavior:' -ForegroundColor Cyan
    Write-Host '  -DirectIso                    Jump directly to the target release'
    Write-Host '  -AllowFallback                Allow fallback methods if ISO/media fails'
    Write-Host '  -NoReboot                     Do not reboot automatically'
    Write-Host '  -ForceOnlineUpdate            Prefer online update paths'
    Write-Host ''
    Write-Host 'USB/media:' -ForegroundColor Cyan
    Write-Host '  -CreateUsb                    Build USB media from acquired ISO/media'
    Write-Host '  -UsbDiskNumber <n>            Target USB disk number'
    Write-Host '  -UsbDiskId <id>               Target USB disk unique ID'
    Write-Host '  -KeepIso                      Keep ISO after USB creation'
    Write-Host '  -UsbPartitionStyle <gpt|mbr>  Partition style for USB media'
    Write-Host ''
    Write-Host 'Source selection:' -ForegroundColor Cyan
    Write-Host '  -PreferredSource <id>         Prefer a source first'
    Write-Host '  -ForceSource <id>             Use only a specific source'
    Write-Host '  -AllowDeadSources             Allow explicit selection of dead sources'
    Write-Host ''
    Write-Host 'Source IDs:' -ForegroundColor Cyan
    Write-Host '  WU_DIRECT, ESD_CATALOG, FIDO, MCT, ASSISTANT, WINDOWS_UPDATE'
    Write-Host '  LEGACY_XML, LEGACY_CAB, LEGACY_MCT_X64, LEGACY_MCT_X86'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  .\wfu-tool.ps1 -Mode Headless -TargetVersion 25H2 -NoReboot'
    Write-Host '  .\wfu-tool.ps1 -ConfigPath .\configs\job.ini -Mode Headless'
    Write-Host '  .\wfu-tool.ps1 -Mode CreateUsb -TargetVersion 25H2 -UsbDiskNumber 3'
    Write-Host ''
}

if ($Help) {
    Show-WfuCliHelp
    return
}

# Use strict mode but handle errors ourselves -- never let the script die silently
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Load the local Windows Update client for direct release metadata.
$wuClientScript = Join-Path $PSScriptRoot 'wfu-tool-windows-update.ps1'
if (Test-Path $wuClientScript) {
    . $wuClientScript
} else {
    Write-Warning "wfu-tool-windows-update.ps1 not found at $wuClientScript"
}

# Track current phase for cancellation diagnostics
$Script:CurrentPhase = 'Initializing'
$Script:Cancelled = $false
$Script:StartTime = Get-Date
$Script:ResolvedOptions = $null
$Script:CheckpointState = $null
$Script:RuntimeArtifacts = [ordered]@{}

# =====================================================================
# Region: Constants & Version Map
# =====================================================================

$Script:VersionMap = [ordered]@{
    'W10_1507'  = @{ Build = 10240; DisplayVersion = '1507';  OS = 'Windows 10' }
    'W10_1511'  = @{ Build = 10586; DisplayVersion = '1511';  OS = 'Windows 10' }
    'W10_1607'  = @{ Build = 14393; DisplayVersion = '1607';  OS = 'Windows 10' }
    'W10_1703'  = @{ Build = 15063; DisplayVersion = '1703';  OS = 'Windows 10' }
    'W10_1709'  = @{ Build = 16299; DisplayVersion = '1709';  OS = 'Windows 10' }
    'W10_1803'  = @{ Build = 17134; DisplayVersion = '1803';  OS = 'Windows 10' }
    'W10_1809'  = @{ Build = 17763; DisplayVersion = '1809';  OS = 'Windows 10' }
    'W10_1903'  = @{ Build = 18362; DisplayVersion = '1903';  OS = 'Windows 10' }
    'W10_1909'  = @{ Build = 18363; DisplayVersion = '1909';  OS = 'Windows 10' }
    'W10_2004'  = @{ Build = 19041; DisplayVersion = '2004';  OS = 'Windows 10' }
    'W10_20H2'  = @{ Build = 19042; DisplayVersion = '20H2';  OS = 'Windows 10' }
    'W10_21H1'  = @{ Build = 19043; DisplayVersion = '21H1';  OS = 'Windows 10' }
    'W10_21H2'  = @{ Build = 19044; DisplayVersion = '21H2';  OS = 'Windows 10' }
    'W10_22H2'  = @{ Build = 19045; DisplayVersion = '22H2';  OS = 'Windows 10' }
    '21H2'      = @{ Build = 22000; DisplayVersion = '21H2';  OS = 'Windows 11' }
    '22H2'      = @{ Build = 22621; DisplayVersion = '22H2';  OS = 'Windows 11' }
    '23H2'      = @{ Build = 22631; DisplayVersion = '23H2';  OS = 'Windows 11' }
    '24H2'      = @{ Build = 26100; DisplayVersion = '24H2';  OS = 'Windows 11' }
    '25H2'      = @{ Build = 26200; DisplayVersion = '25H2';  OS = 'Windows 11' }
}

$Script:UpgradeChain = @(
    @{
        From        = 'W10_1507'
        To          = 'W10_1511'
        Method      = 'FeatureUpdate'
        MinBuild    = 10240
        TargetBuild = 10586
        Description = 'Full feature update from 1507 to 1511'
    },
    @{
        From        = 'W10_1511'
        To          = 'W10_1607'
        Method      = 'FeatureUpdate'
        MinBuild    = 10586
        TargetBuild = 14393
        Description = 'Full feature update from 1511 to 1607'
    },
    @{
        From        = 'W10_1607'
        To          = 'W10_1703'
        Method      = 'FeatureUpdate'
        MinBuild    = 14393
        TargetBuild = 15063
        Description = 'Full feature update from 1607 to 1703'
    },
    @{
        From        = 'W10_1703'
        To          = 'W10_1709'
        Method      = 'FeatureUpdate'
        MinBuild    = 15063
        TargetBuild = 16299
        Description = 'Full feature update from 1703 to 1709'
    },
    @{
        From        = 'W10_1709'
        To          = 'W10_1803'
        Method      = 'FeatureUpdate'
        MinBuild    = 16299
        TargetBuild = 17134
        Description = 'Full feature update from 1709 to 1803'
    },
    @{
        From        = 'W10_1803'
        To          = 'W10_1809'
        Method      = 'FeatureUpdate'
        MinBuild    = 17134
        TargetBuild = 17763
        Description = 'Full feature update from 1803 to 1809'
    },
    @{
        From        = 'W10_1809'
        To          = 'W10_1903'
        Method      = 'FeatureUpdate'
        MinBuild    = 17763
        TargetBuild = 18362
        Description = 'Full feature update from 1809 to 1903'
    },
    @{
        From        = 'W10_1903'
        To          = 'W10_1909'
        Method      = 'EnablementPackage'
        MinBuild    = 18362
        TargetBuild = 18363
        Description = 'Enablement package -- minor build bump (18362 -> 18363)'
    },
    @{
        From        = 'W10_1909'
        To          = 'W10_2004'
        Method      = 'FeatureUpdate'
        MinBuild    = 18363
        TargetBuild = 19041
        Description = 'Full feature update from 1909 to 2004'
    },
    @{
        From        = 'W10_2004'
        To          = 'W10_20H2'
        Method      = 'EnablementPackage'
        MinBuild    = 19041
        TargetBuild = 19042
        Description = 'Enablement package -- minor build bump (19041 -> 19042)'
    },
    @{
        From        = 'W10_20H2'
        To          = 'W10_21H1'
        Method      = 'EnablementPackage'
        MinBuild    = 19042
        TargetBuild = 19043
        Description = 'Enablement package -- minor build bump (19042 -> 19043)'
    },
    @{
        From        = 'W10_21H1'
        To          = 'W10_21H2'
        Method      = 'EnablementPackage'
        MinBuild    = 19043
        TargetBuild = 19044
        Description = 'Enablement package -- minor build bump (19043 -> 19044)'
    },
    @{
        From        = 'W10_21H2'
        To          = 'W10_22H2'
        Method      = 'EnablementPackage'
        MinBuild    = 19044
        TargetBuild = 19045
        Description = 'Enablement package -- minor build bump (19044 -> 19045)'
    },
    @{
        From        = '21H2'
        To          = '22H2'
        Method      = 'FeatureUpdate'
        MinBuild    = 22000
        TargetBuild = 22621
        Description = 'Full feature update from 21H2 to 22H2'
    },
    @{
        From        = '22H2'
        To          = '23H2'
        Method      = 'EnablementPackage'
        MinBuild    = 22621
        TargetBuild = 22631
        KBArticle   = 'KB5027397'
        Description = 'Enablement package -- minor build bump (22621 -> 22631)'
    },
    @{
        From        = '23H2'
        To          = '24H2'
        Method      = 'FeatureUpdate'
        MinBuild    = 22631
        TargetBuild = 26100
        Description = 'Full feature update from 23H2 to 24H2'
    },
    @{
        From        = '24H2'
        To          = '25H2'
        Method      = 'FeatureUpdate'
        MinBuild    = 26100
        TargetBuild = 26200
        Description = 'Feature update from 24H2 to 25H2'
    }
)

$Script:ResumeRegKey    = 'HKLM:\SOFTWARE\wfu-tool'
$Script:ResumeValueName = 'ResumeAfterReboot'
$Script:RunOnceKey      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'

# Track errors for the diagnostic dump at the end
$Script:ErrorLog = [System.Collections.ArrayList]::new()

# =====================================================================
# Region: Module Loader
# =====================================================================

$moduleRoot = Join-Path $PSScriptRoot 'modules\Upgrade'
$moduleFiles = @(
    'Core.ps1',
    'Automation.ps1',
    'SystemHealth.ps1',
    'UpgradePreparation.ps1',
    'Assistant.ps1',
    'LegacyMedia.ps1',
    'DownloadSources.ps1',
    'MediaTools.ps1'
)

foreach ($moduleFile in $moduleFiles) {
    $modulePath = Join-Path $moduleRoot $moduleFile
    if (-not (Test-Path $modulePath)) {
        throw "Required module file not found: $modulePath"
    }
    . $modulePath
}

function Get-WfuEngineCliOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$BoundParameters
    )

    $cli = [ordered]@{}
    foreach ($name in @(
        'ConfigPath','Mode','Interactive','Headless','TargetVersion','NoReboot','LogPath',
        'DownloadPath','ForceOnlineUpdate','MaxRetries','DirectIso','CreateUsb','UsbDiskNumber',
        'UsbDiskId','KeepIso','UsbPartitionStyle','PreferredSource','ForceSource',
        'AllowDeadSources','CheckpointPath','SessionId','ResumeFromCheckpoint','AllowFallback',
        'SkipBypasses','SkipBlockerRemoval','SkipTelemetry','SkipRepair','SkipCumulativeUpdates',
        'SkipNetworkCheck','SkipDiskCheck','SkipDirectEsd','SkipEsd','SkipFido','SkipMct',
        'SkipAssistant','SkipWindowsUpdate'
    )) {
        if ($BoundParameters.ContainsKey($name)) {
            $cli[$name] = Get-Variable -Name $name -Scope Script -ValueOnly
        }
    }

    if ($cli.Contains('Interactive') -and $Interactive) {
        $cli['Mode'] = 'Interactive'
    } elseif ($cli.Contains('Headless') -and $Headless) {
        $cli['Mode'] = 'Headless'
    } elseif ($cli.Contains('CreateUsb') -and $CreateUsb) {
        $cli['Mode'] = 'UsbFromIso'
    }

    if ($cli.Contains('Mode') -and $cli['Mode']) {
        $cli['Mode'] = Get-WfuNormalizedMode -Mode $cli['Mode']
    }

    foreach ($transient in @('ConfigPath','Interactive','Headless')) {
        if ($cli.Contains($transient)) {
            $null = $cli.Remove($transient)
        }
    }

    return $cli
}

function Initialize-WfuRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$BoundParameters
    )

    if (-not (Get-Command New-WfuResolvedOptions -ErrorAction SilentlyContinue)) {
        throw 'Automation helpers are unavailable.'
    }

    $cliOptions = Get-WfuEngineCliOptions -BoundParameters $BoundParameters
    $resumeRequested = $BoundParameters.ContainsKey('ResumeFromCheckpoint') -or (
        $BoundParameters.ContainsKey('Mode') -and (Get-WfuNormalizedMode -Mode $Mode) -eq 'Resume'
    )
    $resolved = New-WfuResolvedOptions -ConfigPath $ConfigPath -CliOptions @{}

    if ($resumeRequested -and -not $BoundParameters.ContainsKey('CheckpointPath')) {
        $registryCheckpoint = Get-RegValue $Script:ResumeRegKey 'CheckpointPath'
        $registrySession = Get-RegValue $Script:ResumeRegKey 'SessionId'
        if ($registryCheckpoint) { $resolved.CheckpointPath = $registryCheckpoint }
        if ($registrySession) { $resolved.SessionId = $registrySession }
    }

    if (($resolved.ResumeFromCheckpoint -or $resolved.Mode -eq 'Resume' -or $resumeRequested) -and $resolved.CheckpointPath) {
        $checkpoint = Read-WfuCheckpoint -Path $resolved.CheckpointPath
        if ($checkpoint -and $checkpoint.Options) {
            $resolved = Merge-WfuOptions -Base $resolved -Override $checkpoint.Options
            $Script:CheckpointState = $checkpoint
        } elseif ($resolved.ResumeFromCheckpoint -or $resolved.Mode -eq 'Resume') {
            Write-Log "Checkpoint not found or invalid at $($resolved.CheckpointPath) -- falling back to registry resume state." -Level WARN
        }
    }

    if (@($cliOptions).Count -gt 0) {
        $resolved = Merge-WfuOptions -Base $resolved -Override $cliOptions
    }

    if (-not $resolved.LogPath) {
        $resolved.LogPath = Join-Path $PSScriptRoot 'wfu-tool.log'
    }
    if (-not $resolved.DownloadPath) {
        $resolved.DownloadPath = 'C:\wfu-tool'
    }
    if (-not $resolved.SessionId) {
        $resolved.SessionId = [guid]::NewGuid().ToString()
    }
    if (-not $resolved.CheckpointPath) {
        $resolved.CheckpointPath = Get-WfuCheckpointPath -DownloadPath $resolved.DownloadPath -SessionId $resolved.SessionId
    }
    if (-not $resolved.Mode) {
        $resolved.Mode = 'Interactive'
    }
    $resolved.Mode = Get-WfuNormalizedMode -Mode $resolved.Mode

    switch ($resolved.Mode) {
        'CreateUsb' {
            $resolved.Mode = 'UsbFromIso'
            $resolved.CreateUsb = $true
            $resolved.DirectIso = $true
        }
        'Headless' {
            $resolved.Mode = 'AutomatedUpgrade'
        }
        'UsbFromIso' {
            $resolved.CreateUsb = $true
            $resolved.DirectIso = $true
        }
        'IsoDownload' {
            $resolved.CreateUsb = $false
            $resolved.DirectIso = $true
        }
        'AutomatedUpgrade' {
            if (-not $resolved.DirectIso) {
                $resolved.DirectIso = $true
            }
        }
    }

    if ($resolved.CreateUsb -and $resolved.Mode -ne 'UsbFromIso') {
        $resolved.Mode = 'UsbFromIso'
        $resolved.DirectIso = $true
    }

    if ($resolved.Mode -eq 'AutomatedUpgrade' -or $resolved.Mode -eq 'UsbFromIso' -or $resolved.Mode -eq 'IsoDownload') {
        $headlessErrors = @(Test-WfuHeadlessRequirements -Options $resolved)
        if ($headlessErrors.Count -gt 0) {
            throw ($headlessErrors -join ' ')
        }
    }

    return $resolved
}

function Apply-WfuRuntimeOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Options
    )

    $Script:ResolvedOptions = $Options
    $Script:Mode = [string]$Options.Mode
    $Script:TargetVersion = [string]$Options.TargetVersion
    $Script:NoReboot = [bool]$Options.NoReboot
    $Script:LogPath = [string]$Options.LogPath
    $Script:DownloadPath = [string]$Options.DownloadPath
    $Script:ForceOnlineUpdate = [bool]$Options.ForceOnlineUpdate
    $Script:MaxRetries = [int]$Options.MaxRetries
    $Script:DirectIso = [bool]$Options.DirectIso
    $Script:CreateUsb = [bool]$Options.CreateUsb
    $Script:UsbDiskNumber = $Options.UsbDiskNumber
    $Script:UsbDiskId = $Options.UsbDiskId
    $Script:KeepIso = [bool]$Options.KeepIso
    $Script:UsbPartitionStyle = [string]$Options.UsbPartitionStyle
    $Script:PreferredSource = [string]$Options.PreferredSource
    $Script:ForceSource = [string]$Options.ForceSource
    $Script:AllowDeadSources = [bool]$Options.AllowDeadSources
    $Script:CheckpointPath = [string]$Options.CheckpointPath
    $Script:SessionId = [string]$Options.SessionId
    $Script:ResumeFromCheckpoint = [bool]$Options.ResumeFromCheckpoint
    $Script:AllowFallback = [bool]$Options.AllowFallback
    $Script:SkipBypasses = [bool]$Options.SkipBypasses
    $Script:SkipBlockerRemoval = [bool]$Options.SkipBlockerRemoval
    $Script:SkipTelemetry = [bool]$Options.SkipTelemetry
    $Script:SkipRepair = [bool]$Options.SkipRepair
    $Script:SkipCumulativeUpdates = [bool]$Options.SkipCumulativeUpdates
    $Script:SkipNetworkCheck = [bool]$Options.SkipNetworkCheck
    $Script:SkipDiskCheck = [bool]$Options.SkipDiskCheck
    $Script:SkipDirectEsd = [bool]$Options.SkipDirectEsd
    $Script:SkipEsd = [bool]$Options.SkipEsd
    $Script:SkipFido = [bool]$Options.SkipFido
    $Script:SkipMct = [bool]$Options.SkipMct
    $Script:SkipAssistant = [bool]$Options.SkipAssistant
    $Script:SkipWindowsUpdate = [bool]$Options.SkipWindowsUpdate

    if (-not (Test-Path $Script:DownloadPath)) {
        New-Item -ItemType Directory -Path $Script:DownloadPath -Force | Out-Null
    }

    if ($Script:LogPath -and -not (Test-Path $Script:LogPath)) {
        New-Item -ItemType File -Path $Script:LogPath -Force | Out-Null
    }
}

function Get-WfuModeLabel {
    [CmdletBinding()]
    param([string]$Mode)

    switch (Get-WfuNormalizedMode -Mode $Mode) {
        'Interactive' { 'Interactive' }
        'IsoDownload' { 'ISO download only' }
        'UsbFromIso' { 'ISO to USB media' }
        'AutomatedUpgrade' { 'Automated in-place upgrade' }
        'Resume' { 'Resume' }
        default { $Mode }
    }
}

function Update-WfuRuntimeCheckpoint {
    [CmdletBinding()]
    param(
        [string]$Stage,
        [string]$CurrentVersion,
        [string]$CurrentStep,
        [string]$NextStep,
        [string]$SelectedSource
    )

    if (-not $Script:ResolvedOptions -or -not (Get-Command Save-WfuCheckpoint -ErrorAction SilentlyContinue)) {
        return
    }
    if (-not $Script:ResolvedOptions.CheckpointPath) {
        return
    }

    $artifacts = [ordered]@{
        IsoPath             = if ($Script:RuntimeArtifacts.Contains('IsoPath')) { $Script:RuntimeArtifacts['IsoPath'] } else { $null }
        StagedMediaPath     = if ($Script:RuntimeArtifacts.Contains('StagedMediaPath')) { $Script:RuntimeArtifacts['StagedMediaPath'] } else { $null }
        LegacyWorkspace     = if ($Script:RuntimeArtifacts.Contains('LegacyWorkspace')) { $Script:RuntimeArtifacts['LegacyWorkspace'] } else { $null }
        DownloadedArtifacts = if ($Script:RuntimeArtifacts.Contains('DownloadedArtifacts')) { $Script:RuntimeArtifacts['DownloadedArtifacts'] } else { $null }
    }

    $null = Save-WfuCheckpoint -Path $Script:ResolvedOptions.CheckpointPath `
        -Options $Script:ResolvedOptions `
        -CurrentVersion $CurrentVersion `
        -TargetVersion $Script:ResolvedOptions.TargetVersion `
        -CurrentStep $CurrentStep `
        -NextStep $NextStep `
        -SelectedSource $SelectedSource `
        -Stage $Stage `
        -Artifacts $artifacts
}

function Invoke-WfuUsbWriterIfAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    if (-not $Script:ResolvedOptions.CreateUsb) {
        return $true
    }

    $candidateNames = @(
        'Write-WfuUsbMedia',
        'Invoke-WfuUsbMedia',
        'New-WfuUsbMedia',
        'Invoke-UsbMediaCreation',
        'Start-WfuUsbCreation'
    )

    foreach ($name in $candidateNames) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }

        $paramNames = @($cmd.Parameters.Keys)
        $usbArgs = @{ IsoPath = $IsoPath }
        if ($paramNames -contains 'UsbDiskNumber') {
            $usbArgs['UsbDiskNumber'] = $Script:ResolvedOptions.UsbDiskNumber
        } elseif ($paramNames -contains 'DiskNumber') {
            $usbArgs['DiskNumber'] = $Script:ResolvedOptions.UsbDiskNumber
        }
        if ($paramNames -contains 'UsbDiskId') {
            $usbArgs['UsbDiskId'] = $Script:ResolvedOptions.UsbDiskId
        } elseif ($paramNames -contains 'DiskId') {
            $usbArgs['DiskId'] = $Script:ResolvedOptions.UsbDiskId
        }
        if ($paramNames -contains 'PartitionStyle') {
            $usbArgs['PartitionStyle'] = $Script:ResolvedOptions.UsbPartitionStyle
        }
        if ($paramNames -contains 'KeepIso') {
            $usbArgs['KeepIso'] = $Script:ResolvedOptions.KeepIso
        }
        if ($paramNames -contains 'CheckpointPath') {
            $usbArgs['CheckpointPath'] = $Script:ResolvedOptions.CheckpointPath
        }
        if ($paramNames -contains 'SessionId') {
            $usbArgs['SessionId'] = $Script:ResolvedOptions.SessionId
        }

        try {
            $result = & $cmd @usbArgs
            return [bool]$result
        } catch {
            Write-Log "  USB writer $name failed: $_" -Level WARN
        }
    }

    Write-Log '  CreateUsb mode requested, but no USB writer helper is available.' -Level WARN
    return $false
}

function Invoke-LegacyWindows10MediaCreation {
    <#
    .SYNOPSIS
        Stages pinned legacy Windows 10 media artifacts and runs the matching MCT build.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$OutputIsoPath
    )

    if (-not (Get-Command Get-LegacyMediaSpec -ErrorAction SilentlyContinue)) {
        Write-Log "  Legacy media helpers are unavailable for $Version." -Level ERROR
        return $false
    }

    $spec = Get-LegacyMediaSpec -Version $Version
    if (-not $spec) {
        Write-Log "  No legacy media manifest entry found for $Version." -Level ERROR
        return $false
    }

    $sysLang = Get-SystemLanguageCode
    $sysEdition = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
    if (-not $sysEdition) { $sysEdition = 'Professional' }
    $mctEdition = switch -Regex ($sysEdition) {
        'Enterprise' { 'Enterprise' }
        'Education'  { 'Education' }
        'Core'       { 'HomeBasic' }
        'Home'       { 'HomeBasic' }
        default      { 'Professional' }
    }
    $omitMediaEditionArg = -not [bool]$spec.SupportsMediaEditionArg

    if (Get-Command Invoke-LegacyMctIsoCreation -ErrorAction SilentlyContinue) {
        $legacyRoot = Join-Path $DownloadPath 'LegacyMedia'
        if ($PSCmdlet.ShouldProcess($Version, "Create legacy $Version ISO via pinned MCT")) {
            return (Invoke-LegacyMctIsoCreation -Version $Version `
                -Language $sysLang `
                -Edition $mctEdition `
                -Arch 'x64' `
                -OutputIsoPath $OutputIsoPath `
                -BasePath $legacyRoot)
        }
        return $false
    }

    $legacyRoot = Join-Path $DownloadPath "LegacyMedia\$Version"
    $mctRoot = Join-Path $legacyRoot 'MCT'
    $cacheRoot = Join-Path $legacyRoot 'Cache'
    $mctPath = Join-Path $mctRoot 'MediaCreationTool.exe'

    foreach ($dir in @($legacyRoot, $mctRoot, $cacheRoot)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    }

    $sources = @()
    if (Get-Command Get-LegacyMediaSourceDescriptors -ErrorAction SilentlyContinue) {
        $sources = @(Get-LegacyMediaSourceDescriptors -Version $Version)
    }

    $mctSource = $sources | Where-Object { $_.Kind -eq 'MCTEXE' } | Select-Object -First 1
    if (-not $mctSource) {
        $mctSource = [pscustomobject]@{
            Url      = $spec.MctUrl
            FileName = (Split-Path $spec.MctUrl -Leaf)
            Notes    = 'Pinned legacy MCT'
        }
    }

    if (-not $mctSource -or -not $mctSource.Url) {
        Write-Log "  Legacy MCT source URL missing for $Version." -Level ERROR
        return $false
    }

    $needsMctDownload = (-not (Test-Path $mctPath) -or (Get-Item $mctPath -ErrorAction SilentlyContinue).Length -lt 1MB)
    if ($needsMctDownload) {
        Write-Log "  Downloading pinned legacy MCT for $Version..." -Level INFO
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $mctSource.Url -OutFile $mctPath -UseBasicParsing -ErrorAction Stop
        } finally {
            $ProgressPreference = 'Continue'
        }
    } else {
        Write-Log "  Using cached legacy MCT: $mctPath" -Level SUCCESS
    }

    if (-not (Test-Path $mctPath) -or (Get-Item $mctPath -ErrorAction SilentlyContinue).Length -lt 1MB) {
        Write-Log "  Legacy MCT download failed for $Version." -Level ERROR
        return $false
    }

    if ($PSCmdlet.ShouldProcess($mctPath, "Create legacy $Version ISO")) {
        Write-Log "  Creating legacy ISO: $Version lang=$sysLang edition=$(if ($omitMediaEditionArg) { 'auto' } else { $mctEdition })" -Level INFO
        return (Start-MctIsoCreation -MctExePath $mctPath `
            -OutputIsoPath $OutputIsoPath `
            -LangCode $sysLang `
            -Edition $mctEdition `
            -Arch 'x64' `
            -OmitMediaEditionArg:$omitMediaEditionArg)
    }

    return $false
}

function Install-ViaIsoUpgrade {
    <#
    .SYNOPSIS
        Downloads install media for the target release,
        applies setup compatibility patches (appraiserres.dll, hwreqchk.dll),
        and runs setup.exe with /Product Server trick.
        If an existing ISO is found in DownloadPath, it uses that directly.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([hashtable]$Step)

    $targetInfo = $Script:VersionMap[$Step.To]
    $targetLabel = if ($targetInfo) { "$($targetInfo.OS) $($targetInfo.DisplayVersion)" } else { $Step.To }
    $isLegacyWindows10Target = ($Step.To -like 'W10_*')
    $supportsDirectMetadata = @('25H2','24H2','23H2','22H2','21H2','W10_21H2','W10_22H2') -contains $Step.To
    $supportsEsdCatalog = @('22H2','23H2') -contains $Step.To
    $supportsFido = @('25H2','24H2','23H2','22H2','21H2','W10_20H2','W10_21H2','W10_22H2') -contains $Step.To
    $isoFileName = if ($Step.To) { "$($Step.To).iso" } else { 'Windows.iso' }
    $isoPath = Join-Path $DownloadPath $isoFileName

    # Check for existing ISO first (user may have placed one manually)
    if (Test-Path $isoPath) {
        $isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
        if ($isoSize -gt 3) {
            Write-Log "  Found existing ISO ($isoSize GB): $isoPath" -Level SUCCESS
        } else {
            Write-Log "  Found ISO but it is only $isoSize GB -- likely incomplete. Removing." -Level WARN
            Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Download ISO or ESD if not present
    $esdPath = Join-Path $DownloadPath "$($Step.To).esd"
    $esdExtractDir = $null

    if ($isLegacyWindows10Target -and -not (Test-Path $isoPath)) {
        Write-Phase "Preparing legacy Windows 10 media for $($Step.To)..."
        Write-Log "  Using pinned legacy media path for $targetLabel..." -Level INFO
        $legacyOk = Invoke-LegacyWindows10MediaCreation -Version $Step.To -OutputIsoPath $isoPath
        Complete-Phase

        if (-not $legacyOk -or -not (Test-Path $isoPath)) {
            Write-Log "  Legacy Windows 10 media acquisition failed for $($Step.To)." -Level ERROR
            return $false
        }
    }

    if (-not (Test-Path $isoPath)) {
        Write-Phase "Downloading $targetLabel media..."
        Write-Log "  No ISO found. Downloading $targetLabel media..."
        $isoDownloaded = $false

        # Count enabled download methods for numbering
        $dlMethods = @()
        if (-not $SkipDirectEsd -and $supportsDirectMetadata)  { $dlMethods += 'DirectMetadata' }
        if (-not $SkipEsd -and $supportsEsdCatalog)  { $dlMethods += 'ESD' }
        if (-not $SkipFido -and $supportsFido) { $dlMethods += 'Fido' }
        if (-not $SkipMct)  { $dlMethods += 'MCT' }
        $dlTotal = $dlMethods.Count
        $dlNum = 0

        # ================================================================
        # Method A0: Direct WU/direct release ESD (permanent CDN, ALL versions)
        # This is the most reliable method -- direct Microsoft CDN URLs
        # obtained from Microsoft's own Windows Update endpoints.
        # ================================================================
        if (-not $SkipDirectEsd -and $supportsDirectMetadata -and -not $isoDownloaded) {
            $dlNum++
            # Detect system language and edition for direct metadata download
            $releaseLang = (Get-SystemLanguageCode).ToLower()
            $releaseEdition = (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID')
            if (-not $releaseEdition) { $releaseEdition = 'professional' }
            $releaseEdition = $releaseEdition.ToLower()
            Write-Log "  [Download $dlNum/$dlTotal] Trying direct WU/direct release ESD for $($Step.To) ($releaseLang/$releaseEdition)..."
            $releaseInfo = Get-ReleaseEsd -Version $Step.To -Language $releaseLang -Edition $releaseEdition

            if ($releaseInfo) {
                $releaseDlOk = Start-DownloadWithProgress -Url $releaseInfo.Url -Destination $esdPath `
                    -Description "$($Step.To) ESD from direct WU ($([math]::Round($releaseInfo.Size / 1MB)) MB)"

                if ($releaseDlOk -and (Test-Path $esdPath)) {
                    if ($releaseInfo.Sha1) {
                        $hashOk = Test-FileHash -FilePath $esdPath -ExpectedHash $releaseInfo.Sha1 -Algorithm SHA1
                        if (-not $hashOk) {
                            Write-Log '  Direct WU ESD hash mismatch -- removing.' -Level ERROR
                            Remove-Item $esdPath -Force -ErrorAction SilentlyContinue
                            $releaseDlOk = $false
                        }
                    } else {
                        $esdExtractDir = Convert-EsdToIso -EsdPath $esdPath -OutputDir $DownloadPath -TargetEdition 'Professional'
                        if ($esdExtractDir -and (Test-Path (Join-Path $esdExtractDir 'setup.exe'))) {
                            Write-Log '  Direct WU ESD extracted with setup.exe -- ready to upgrade.' -Level SUCCESS
                            $isoDownloaded = $true
                        } else {
                            Write-Log '  Direct WU ESD extracted but setup.exe not found.' -Level WARN
                        }
                    }
                }
            }

            if (-not $isoDownloaded) {
                Write-Log '  Direct WU ESD: could not obtain or extract.' -Level WARN
            }
        } elseif (-not $isoDownloaded -and $SkipDirectEsd) {
            Write-Log '  Direct WU ESD: SKIPPED (disabled)' -Level DEBUG
        }

        # ================================================================
        # Method A1: ESD from products.cab catalog (permanent CDN links + SHA1)
        # Only available for 22H2/23H2. Returns $null for 24H2/25H2.
        # ================================================================
        if (-not $SkipEsd -and $supportsEsdCatalog -and -not $isoDownloaded) {
        $dlNum++
        Write-Log "  [Download $dlNum/$dlTotal] Trying ESD catalog for $($Step.To)..."
        $catLang = (Get-SystemLanguageCode).ToLower()
        $esdInfo = Get-EsdDownloadFromCatalog -Version $Step.To -Language $catLang -Arch 'x64'
        # Only retry with en-gb if the catalog exists but didn't have en-us
        # (Don't retry if there's no catalog for this version at all)
        if (-not $esdInfo -and ($Step.To -eq '22H2' -or $Step.To -eq '23H2')) {
            $esdInfo = Get-EsdDownloadFromCatalog -Version $Step.To -Language 'en-gb' -Arch 'x64'
        }

        if ($esdInfo) {
            $esdDlOk = Start-DownloadWithProgress -Url $esdInfo.Url -Destination $esdPath -Description "Windows 11 ESD ($([math]::Round($esdInfo.Size / 1MB)) MB)"

            if ($esdDlOk -and (Test-Path $esdPath)) {
                # Verify SHA1 hash
                $hashOk = Test-FileHash -FilePath $esdPath -ExpectedHash $esdInfo.Sha1 -Algorithm SHA1
                if (-not $hashOk) {
                    Write-Log '  ESD hash mismatch -- file may be corrupted. Removing.' -Level ERROR
                    Remove-Item $esdPath -Force -ErrorAction SilentlyContinue
                } else {
                    # Convert ESD to installable media
                    $esdExtractDir = Convert-EsdToIso -EsdPath $esdPath -OutputDir $DownloadPath
                    if ($esdExtractDir) {
                        # We don't need an ISO -- we can run setup.exe from the extracted WIM directly
                        # But we need setup.exe which is in ESD index 2
                        # If extraction succeeded, check for setup.exe
                        $esdSetup = Join-Path $esdExtractDir 'setup.exe'
                        if (Test-Path $esdSetup) {
                            Write-Log '  ESD extracted with setup.exe -- ready to upgrade.' -Level SUCCESS
                            $isoDownloaded = $true
                        } else {
                            Write-Log '  ESD extracted but setup.exe not found -- will try ISO methods.' -Level WARN
                        }
                    }
                }
            }
        }

        } else {
            Write-Log '  ESD catalog download: SKIPPED (disabled)' -Level DEBUG
        }  # end SkipEsd

        # ================================================================
        # Method B: Direct ISO download via Microsoft API (Fido approach)
        # URLs are time-limited (24h) but give a full bootable ISO.
        # ================================================================
        if (-not $isoDownloaded -and -not $SkipFido -and $supportsFido) {
            $dlNum++
            Write-Log "  [Download $dlNum/$dlTotal] Trying direct ISO from Microsoft API for $($Step.To)..."
            $sysLangIso = Get-SystemLanguageCode
            $msLangName = ConvertTo-MicrosoftLanguageName $sysLangIso
            Write-Log "  Locale: $sysLangIso -> API name: $msLangName" -Level DEBUG

            # Build language attempt list: mapped system language first, then English fallbacks
            $langAttempts = @('English International', 'English')
            if ($msLangName -and $msLangName -ne 'English' -and $msLangName -ne 'English International') {
                $langAttempts = @($msLangName) + $langAttempts
            }
            $directUrl = $null
            foreach ($langTry in $langAttempts) {
                $directUrl = Get-DirectIsoDownloadUrl -Language $langTry -Arch 'x64' -Version $Step.To
                if ($directUrl) { break }
            }

            if ($directUrl) {
                $isoDlOk = Start-DownloadWithProgress -Url $directUrl -Destination $isoPath -Description "$targetLabel ISO"

                if ($isoDlOk -and (Test-Path $isoPath)) {
                    $dlSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
                    if ($dlSize -lt 3) {
                        Write-Log "  Downloaded ISO is only $dlSize GB -- likely corrupted. Removing." -Level WARN
                        Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
                    } else {
                        Write-Log "  ISO downloaded: $dlSize GB" -Level SUCCESS
                        $isoDownloaded = $true
                    }
                }
            } else {
                Write-Log '  Could not get direct download URL from Microsoft API.' -Level WARN
            }
        } elseif (-not $isoDownloaded) {
            Write-Log '  Fido ISO download: SKIPPED (disabled)' -Level DEBUG
        }  # end SkipFido

        # ================================================================
        # Method C: Media Creation Tool unattended ISO
        # Uses /Action CreateMedia with proper locale and edition detection.
        # For legacy Windows 10 targets, prefer a pinned release-specific MCT executable.
        # ================================================================
        if (-not $isoDownloaded -and -not $SkipMct) {
            $dlNum++
            Write-Log "  [Download $dlNum/$dlTotal] Using Media Creation Tool (unattended)..."

            # Detect system language for MCT
            $sysLang = Get-SystemLanguageCode
            # Detect current edition for MCT media selection
            $sysEdition = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
            if (-not $sysEdition) { $sysEdition = 'Professional' }
            # MCT only supports specific edition names
            $mctEdition = switch -Regex ($sysEdition) {
                'Enterprise'   { 'Enterprise' }
                'Education'    { 'Education' }
                'Core'         { 'HomeBasic' }
                'Home'         { 'HomeBasic' }
                default        { 'Professional' }
            }

            $mctUrl = 'https://go.microsoft.com/fwlink/?linkid=2156295'
            $omitMediaEditionArg = $false
            if ($isLegacyWindows10Target -and (Get-Command 'Get-LegacyMediaSpec' -ErrorAction SilentlyContinue)) {
                $legacySpec = Get-LegacyMediaSpec -Version $Step.To
                if ($legacySpec) {
                    if ($legacySpec.PreferredMctUrl) {
                        $mctUrl = $legacySpec.PreferredMctUrl
                    } elseif ($legacySpec.MctUrl) {
                        $mctUrl = $legacySpec.MctUrl
                    }
                    $omitMediaEditionArg = -not [bool]$legacySpec.SupportsMediaEditionArg
                }
            }
            $mctDir  = Join-Path $DownloadPath 'MCT'
            $mctPath = Join-Path $mctDir 'MediaCreationTool.exe'

            try {
                # Create MCT working directory
                if (-not (Test-Path $mctDir)) {
                    New-Item -ItemType Directory -Path $mctDir -Force -ErrorAction Stop | Out-Null
                }

                # Download MCT if needed
                if (-not (Test-Path $mctPath) -or (Get-Item $mctPath -ErrorAction SilentlyContinue).Length -lt 1MB) {
                    Write-Log '  Downloading Media Creation Tool...'
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $mctUrl -OutFile $mctPath -UseBasicParsing -ErrorAction Stop
                    $ProgressPreference = 'Continue'
                    Write-Log "  MCT downloaded ($([math]::Round((Get-Item $mctPath).Length / 1MB)) MB)" -Level SUCCESS
                }

                if ((Get-Item $mctPath -ErrorAction SilentlyContinue).Length -gt 1MB) {
                    $editionLabel = if ($omitMediaEditionArg) { 'auto' } else { $mctEdition }
                    Write-Log "  Creating ISO: lang=$sysLang edition=$editionLabel arch=x64"
                    if ($PSCmdlet.ShouldProcess($mctPath, "Create ISO via MCT ($sysLang/$mctEdition)")) {
                        $mctResult = Start-MctIsoCreation -MctExePath $mctPath `
                            -OutputIsoPath $isoPath `
                            -LangCode $sysLang `
                            -Edition $mctEdition `
                            -Arch 'x64' `
                            -OmitMediaEditionArg:$omitMediaEditionArg

                        if ($mctResult -eq $true) {
                            $isoDownloaded = $true
                            Write-Log '  ISO created via Media Creation Tool.' -Level SUCCESS
                        }
                    }
                }
            } catch {
                Write-Log "  MCT method failed: $_" -Level WARN
            }
        } elseif (-not $isoDownloaded) {
            Write-Log '  MCT ISO download: SKIPPED (disabled)' -Level DEBUG
        }  # end SkipMct

        if (-not $isoDownloaded) {
            $enabledList = $dlMethods -join ', '
            if (-not $enabledList) { $enabledList = '(none enabled!)' }
            Write-Log "  All enabled download methods failed ($enabledList)." -Level ERROR
            Write-Log '  Download manually from the appropriate Microsoft software download page or use a pinned legacy media tool build.' -Level WARN
            Write-Log "  Save as: $isoPath" -Level WARN
            return $false
        }
    }

    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.Mode -eq 'IsoDownload') {
        $Script:RuntimeArtifacts.IsoPath = $isoPath
        Write-Log "  ISO ready at $isoPath" -Level SUCCESS
        Update-WfuRuntimeCheckpoint -Stage 'iso ready' -CurrentVersion $Step.From -CurrentStep $Step.To -NextStep $null -SelectedSource $PreferredSource
        return $true
    }

    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.CreateUsb) {
        Write-Phase 'Preparing USB media'
        Write-Log '  USB media mode active -- handing off ISO to USB writer.' -Level INFO
        $Script:RuntimeArtifacts.IsoPath = $isoPath
        $usbResult = Invoke-WfuUsbWriterIfAvailable -IsoPath $isoPath
        Complete-Phase
        if ($usbResult) {
            Update-WfuRuntimeCheckpoint -Stage 'usb ready' -CurrentVersion $Step.From -CurrentStep $Step.To -NextStep $null -SelectedSource $PreferredSource
            return $true
        }
        return $false
    }

    # Mount ISO and run setup.exe
    if (-not (Test-Path $isoPath)) {
        return $false
    }

    Write-Phase 'Mounting ISO and preparing setup...'
    Write-Log '  Mounting ISO...'
    try {
        $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
        $driveLetter = ($mountResult | Get-Volume -ErrorAction Stop).DriveLetter
        $mediaRoot = "${driveLetter}:\"
        $setupExe = "${driveLetter}:\setup.exe"
        $sourcesDir = "${driveLetter}:\sources"

        if (-not (Test-Path $setupExe)) {
            Write-Log "  setup.exe not found on mounted ISO at $setupExe" -Level WARN
            Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
            return $false
        }

        Write-Log "  ISO mounted at ${driveLetter}:\" -Level SUCCESS

        # ==============================================================
        # MCT compatibility bypass: copy sources to writable location, then patch
        # ISO is read-only so we copy the sources folder to a temp dir
        # and apply the appraiserres.dll + hwreqchk.dll patches there.
        # Apply the compatibility patch set against writable setup media.
        # ==============================================================

        $workDir = Join-Path $DownloadPath 'SetupWork'
        $workSources = Join-Path $workDir 'sources'
        $usePatched = $false

        Write-Phase 'Patching setup files (appraiserres.dll + hwreqchk.dll)...'
        Write-Log '  Applying MCT compatibility bypass patches to setup sources...'
        try {
            # Copy the sources directory to a writable location
            if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $workDir -Force -ErrorAction Stop | Out-Null

            Write-Log '  Copying setup sources to writable directory (this may take a minute)...'
            # Copy everything from ISO root -- setup.exe needs the full structure
            & robocopy.exe "${driveLetter}:\" $workDir /E /NFL /NDL /NJH /NJS /NC /NS /NP 2>$null | Out-Null

            # CRITICAL: Strip read-only attributes from ALL copied files.
            # ISO files are read-only by default and WriteAllBytes/Set-Content will fail.
            Write-Log '  Clearing read-only attributes on copied files...' -Level DEBUG
            & attrib.exe -R "$workDir\*.*" /S /D 2>$null | Out-Null

            if (Test-Path (Join-Path $workDir 'setup.exe')) {

                # Patch 1: Zero-byte appraiserres.dll
                # This makes the appraiser unable to report any hardware failures.
                $appraiserDll = Join-Path $workSources 'appraiserres.dll'
                if (Test-Path $appraiserDll) {
                    # Ensure writable then truncate to 0 bytes
                    Set-ItemProperty $appraiserDll -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    [IO.File]::WriteAllBytes($appraiserDll, [byte[]]@())
                    Write-Log '  [MCT] appraiserres.dll zeroed (0 bytes)' -Level SUCCESS
                } else {
                    # Create empty file
                    New-Item -ItemType File -Path $appraiserDll -Force -ErrorAction SilentlyContinue | Out-Null
                    Write-Log '  [MCT] appraiserres.dll created as empty' -Level SUCCESS
                }

                # Patch 2: hwreqchk.dll binary patch
                # Patches "SQ_TpmVersion GTE 1" -> "SQ_TpmVersion GTE 0"
                # so the TPM version check passes with any TPM (or none).
                $hwReqDll = Join-Path $workSources 'hwreqchk.dll'
                if (Test-Path $hwReqDll) {
                    Set-ItemProperty $hwReqDll -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                    try {
                        $needle = [Text.Encoding]::UTF8.GetBytes('SQ_TpmVersion GTE 1')
                        $replace = [Text.Encoding]::UTF8.GetBytes('SQ_TpmVersion GTE 0')
                        $bytes = [IO.File]::ReadAllBytes($hwReqDll)
                        $hex = [BitConverter]::ToString($bytes) -replace '-'
                        $searchHex = [BitConverter]::ToString($needle) -replace '-'
                        $patched = $false
                        $offset = 0
                        do {
                            $idx = $hex.IndexOf($searchHex, $offset)
                            if ($idx -gt 0) {
                                $byteIdx = $idx / 2
                                for ($k = 0; $k -lt $replace.Length; $k++) {
                                    $bytes[$byteIdx + $k] = $replace[$k]
                                }
                                $patched = $true
                                $offset = $idx + 2
                            }
                        } until ($idx -lt 0)

                        if ($patched) {
                            # Take ownership and write
                            & takeown.exe /f $hwReqDll /a 2>$null | Out-Null
                            & icacls.exe $hwReqDll /grant *S-1-5-32-544:F 2>$null | Out-Null
                            [IO.File]::WriteAllBytes($hwReqDll, $bytes)
                            Write-Log '  [MCT] hwreqchk.dll patched (TPM GTE 1 -> GTE 0)' -Level SUCCESS
                        } else {
                            Write-Log '  [MCT] hwreqchk.dll: pattern not found (may already be patched or different build)' -Level DEBUG
                        }
                    } catch {
                        Write-Log "  [MCT] hwreqchk.dll patch failed: $_" -Level WARN
                    }
                }

                $usePatched = $true
                $setupExe = Join-Path $workDir 'setup.exe'
                Write-Log '  Patched setup sources ready.' -Level SUCCESS
            } else {
                Write-Log '  Copy failed -- using original ISO directly.' -Level WARN
            }
        } catch {
            Write-Log "  Patch process failed: $_ -- using original ISO directly." -Level WARN
        }

        # ================================================================
        # Run setupprep.exe from sources\
        # CRITICAL: Must use sources\setupprep.exe, NOT root setup.exe!
        # Root setup.exe is a bootstrapper that creates $WINDOWS.~BT,
        # copies files there, and re-downloads appraiserres.dll --
        # overwriting our zeroed version. setupprep.exe runs in-place
        # from the sources directory where our patches are.
        # ================================================================

        # Determine which exe to run and build args
        $setupPrepExe = $null
        $setupWorkDir = $null

        if ($usePatched) {
            $setupPrepExe = Join-Path $workSources 'setupprep.exe'
            $setupWorkDir = $workSources
            if (-not (Test-Path $setupPrepExe)) {
                # Fallback to root setup.exe if setupprep doesn't exist
                $setupPrepExe = Join-Path $workDir 'setup.exe'
                $setupWorkDir = $workDir
                Write-Log '  setupprep.exe not found in sources -- falling back to setup.exe' -Level WARN
            }
        } else {
            $setupPrepExe = $setupExe
            $setupWorkDir = Split-Path $setupExe -Parent
        }

        # Build args for the setup bootstrap path
        $appraiserSize = 1  # assume not zeroed
        if ($usePatched) {
            $appraiserPath = Join-Path $workSources 'appraiserres.dll'
            if (Test-Path $appraiserPath) { $appraiserSize = (Get-Item $appraiserPath).Length }
        }

        if ($appraiserSize -eq 0) {
            # /Product Server trick + /SelfHost
            # NOTE: /Product Server is a BYPASS TRICK, not a Server edition install.
            # It makes setup skip consumer hardware checks. The actual edition
            # installed matches the ISO (Home/Pro/Edu), not Server.
            $setupArgs = '/Product Server /SelfHost /Auto Upgrade /MigChoice Upgrade /Compat IgnoreWarning /MigrateDrivers All /ResizeRecoveryPartition Disable /ShowOOBE None /Telemetry Disable /CompactOS Disable /DynamicUpdate Enable /SkipSummary /Eula Accept'
            Write-Log '  Bypass: /Product Server trick active (NOT installing Server -- this skips HW checks)' -Level SUCCESS
        } else {
            $setupArgs = '/SelfHost /Auto Upgrade /MigChoice Upgrade /Compat IgnoreWarning /MigrateDrivers All /ResizeRecoveryPartition Disable /ShowOOBE None /Telemetry Disable /CompactOS Disable /DynamicUpdate Disable /SkipSummary /Eula Accept'
        }

        if ($PSCmdlet.ShouldProcess($setupPrepExe, "Run setupprep.exe $setupArgs")) {
            Write-Phase "Launching Windows Setup (in-place upgrade)..."
            Write-Log "  Running: $(Split-Path $setupPrepExe -Leaf) $setupArgs"
            Write-Log "  Working dir: $setupWorkDir" -Level DEBUG

            $proc = Start-Process -FilePath $setupPrepExe `
                -ArgumentList $setupArgs `
                -WorkingDirectory $setupWorkDir `
                -PassThru -Wait -ErrorAction Stop

            # Dismount ISO after setup finishes
            try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue } catch { }

            if ($null -eq $proc) {
                Write-Log '  setup.exe process object is null.' -Level WARN
                return $false
            }

            $exitCode = $proc.ExitCode
            Write-Log "  setup.exe exited with code: $exitCode" -Level DEBUG

            # Setup.exe exit codes
            switch ($exitCode) {
                { $_ -eq 0 -or $_ -eq 3010 } {
                    Write-Log '  setup.exe completed successfully!' -Level SUCCESS
                    return $true
                }
                0xC1900101 { Write-Log '  Driver compatibility issue (0xC1900101).' -Level WARN }
                0xC1900200 { Write-Log '  System does not meet minimum requirements (0xC1900200).' -Level WARN }
                0xC1900202 { Write-Log '  System not compatible (0xC1900202).' -Level WARN }
                0xC1900204 { Write-Log '  Migration choice not available (0xC1900204).' -Level WARN }
                0xC1900205 { Write-Log '  COMPAT BLOCK: Hardware/software check failed (0xC1900205). Bypasses may not have been applied.' -Level ERROR }
                0xC1900208 { Write-Log '  Incompatible app blocking upgrade (0xC1900208).' -Level WARN }
                0xC1900210 { Write-Log '  No qualifying Windows 10/11 edition for upgrade (0xC1900210).' -Level WARN }
                0x80070002 { Write-Log '  File not found -- ISO may be corrupted (0x80070002).' -Level WARN }
                0x80070005 { Write-Log '  Access denied -- needs admin (0x80070005).' -Level WARN }
                default    { Write-Log "  setup.exe failed with code $exitCode (0x$("{0:X}" -f $exitCode))." -Level WARN }
            }
        }
    } catch {
        Write-Log "  ISO mount/setup failed: $_" -Level WARN
        try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue } catch { }
    }

    return $false
}

function Start-WindowsUpdateScan {
    # Try multiple methods to trigger a WU scan
    $triggered = $false

    # Method 1: COM API
    try {
        $autoUpdate = New-Object -ComObject Microsoft.Update.AutoUpdate
        $autoUpdate.DetectNow()
        Write-Log '  Windows Update scan initiated (COM).' -Level DEBUG
        $triggered = $true
    } catch { }

    # Method 2: UsoClient
    if (-not $triggered) {
        try {
            & UsoClient.exe StartScan 2>$null
            Write-Log '  Windows Update scan initiated (UsoClient).' -Level DEBUG
            $triggered = $true
        } catch { }
    }

    # Method 3: Scheduled task trigger
    if (-not $triggered) {
        try {
            & schtasks.exe /Run /TN '\Microsoft\Windows\WindowsUpdate\Scheduled Start' 2>$null
            Write-Log '  Windows Update scan initiated (Scheduled Task).' -Level DEBUG
            $triggered = $true
        } catch { }
    }

    if (-not $triggered) {
        Write-Log '  Could not trigger Windows Update scan via any method.' -Level WARN
    }
}

# =====================================================================
# Region: Reboot & Resume
# =====================================================================

function Set-ResumeAfterReboot {
    <#
    .SYNOPSIS
        Registers a Scheduled Task to resume the upgrade after reboot.
        Uses a scheduled task instead of RunOnce because:
        - Runs with SYSTEM privileges (guaranteed admin)
        - Opens a visible terminal window so the user can see progress
        - Can be configured to retry if the first attempt fails
        - Survives multiple reboots if needed (RunOnce fires once and is deleted)
        Also sets a RunOnce fallback in case the scheduled task fails.
    #>
    param([string]$NextTarget)

    # Determine script root (where all our scripts live)
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptRoot)) { $scriptRoot = Split-Path $LogPath -Parent }
    $sessionCheckpoint = if ($Script:ResolvedOptions -and $Script:ResolvedOptions.CheckpointPath) { $Script:ResolvedOptions.CheckpointPath } else { $CheckpointPath }
    $sessionId = if ($Script:ResolvedOptions -and $Script:ResolvedOptions.SessionId) { $Script:ResolvedOptions.SessionId } else { $SessionId }

    # Save state to registry so the resume wrapper can find everything
    try {
        if (-not (Test-Path $Script:ResumeRegKey)) {
            New-Item -Path $Script:ResumeRegKey -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty $Script:ResumeRegKey -Name 'TargetVersion' -Value $TargetVersion -ErrorAction SilentlyContinue
        Set-ItemProperty $Script:ResumeRegKey -Name 'NextStep' -Value $NextTarget -ErrorAction SilentlyContinue
        Set-ItemProperty $Script:ResumeRegKey -Name 'ScriptRoot' -Value $scriptRoot -ErrorAction SilentlyContinue
        Set-ItemProperty $Script:ResumeRegKey -Name 'LogPath' -Value $LogPath -ErrorAction SilentlyContinue
        Set-ItemProperty $Script:ResumeRegKey -Name 'DownloadPath' -Value $DownloadPath -ErrorAction SilentlyContinue
        if ($sessionCheckpoint) { Set-ItemProperty $Script:ResumeRegKey -Name 'CheckpointPath' -Value $sessionCheckpoint -ErrorAction SilentlyContinue }
        if ($sessionId) { Set-ItemProperty $Script:ResumeRegKey -Name 'SessionId' -Value $sessionId -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.Mode) { Set-ItemProperty $Script:ResumeRegKey -Name 'Mode' -Value $Script:ResolvedOptions.Mode -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.CreateUsb) { Set-ItemProperty $Script:ResumeRegKey -Name 'CreateUsb' -Value 1 -Type DWord -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbDiskNumber) { Set-ItemProperty $Script:ResumeRegKey -Name 'UsbDiskNumber' -Value $Script:ResolvedOptions.UsbDiskNumber -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbDiskId) { Set-ItemProperty $Script:ResumeRegKey -Name 'UsbDiskId' -Value $Script:ResolvedOptions.UsbDiskId -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbPartitionStyle) { Set-ItemProperty $Script:ResumeRegKey -Name 'UsbPartitionStyle' -Value $Script:ResolvedOptions.UsbPartitionStyle -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.PreferredSource) { Set-ItemProperty $Script:ResumeRegKey -Name 'PreferredSource' -Value $Script:ResolvedOptions.PreferredSource -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.ForceSource) { Set-ItemProperty $Script:ResumeRegKey -Name 'ForceSource' -Value $Script:ResolvedOptions.ForceSource -ErrorAction SilentlyContinue }
        if ($Script:ResolvedOptions -and $Script:ResolvedOptions.AllowDeadSources) { Set-ItemProperty $Script:ResumeRegKey -Name 'AllowDeadSources' -Value 1 -Type DWord -ErrorAction SilentlyContinue }
        Set-ItemProperty $Script:ResumeRegKey -Name $Script:ResumeValueName -Value 1 -Type DWord -ErrorAction SilentlyContinue
        if ($NoReboot) {
            Set-ItemProperty $Script:ResumeRegKey -Name 'NoReboot' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "Could not save resume state to registry: $_" -Level WARN
    }

    if ($sessionCheckpoint) {
        Update-WfuRuntimeCheckpoint -Stage 'awaiting reboot' -CurrentVersion $TargetVersion -CurrentStep $TargetVersion -NextStep $NextTarget -SelectedSource $ForceSource
    }

    # Build the PowerShell command for the resume wrapper
    $resumeScript = Join-Path $scriptRoot 'resume-wfu-tool.ps1'
    $psArgs = @(
        '-ExecutionPolicy','Bypass',
        '-NoProfile',
        '-File', "`"$resumeScript`"",
        '-ScriptRoot', "`"$scriptRoot`"",
        '-TargetVersion', $TargetVersion,
        '-LogPath', "`"$LogPath`"",
        '-DownloadPath', "`"$DownloadPath`""
    )
    if ($ConfigPath) { $psArgs += @('-ConfigPath', "`"$ConfigPath`"") }
    if ($sessionCheckpoint) { $psArgs += @('-CheckpointPath', "`"$sessionCheckpoint`"") }
    if ($sessionId) { $psArgs += @('-SessionId', "`"$sessionId`"") }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.Mode) { $psArgs += @('-Mode', $Script:ResolvedOptions.Mode) }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.CreateUsb) { $psArgs += '-CreateUsb' }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbDiskNumber) { $psArgs += @('-UsbDiskNumber', $Script:ResolvedOptions.UsbDiskNumber) }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbDiskId) { $psArgs += @('-UsbDiskId', "`"$($Script:ResolvedOptions.UsbDiskId)`"") }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.UsbPartitionStyle) { $psArgs += @('-UsbPartitionStyle', $Script:ResolvedOptions.UsbPartitionStyle) }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.PreferredSource) { $psArgs += @('-PreferredSource', $Script:ResolvedOptions.PreferredSource) }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.ForceSource) { $psArgs += @('-ForceSource', $Script:ResolvedOptions.ForceSource) }
    if ($Script:ResolvedOptions -and $Script:ResolvedOptions.AllowDeadSources) { $psArgs += '-AllowDeadSources' }
    if ($ResumeFromCheckpoint) { $psArgs += '-ResumeFromCheckpoint' }
    if ($NoReboot) { $psArgs += '-NoReboot' }
    $psArgs = $psArgs -join ' '

    $registered = $false

    # --- Primary: Scheduled Task ---
    $taskName = 'wfu-tool-resume'
    try {
        # Remove existing task if present
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        # Create task action -- opens a visible cmd window that runs PowerShell
        # Using cmd /k so the window stays open if there's an error
        $cmdLine = "cmd.exe /k `"title wfu-tool - Resuming & mode con: cols=90 lines=40 & powershell.exe $psArgs & pause`""

        $action = New-ScheduledTaskAction -Execute 'cmd.exe' `
            -Argument "/c `"title wfu-tool - Resuming & mode con: cols=90 lines=40 & powershell.exe $psArgs & echo. & echo   Press any key to close... & pause >nul`""

        # Trigger: at logon of any user (runs once, we delete it when done)
        $trigger = New-ScheduledTaskTrigger -AtLogOn

        # Settings: run with highest privileges, allow on battery, don't stop on idle
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -DontStopOnIdleEnd `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 4)

        # Principal: run as the interactive user with highest privileges
        # Use SID S-1-5-32-544 to resolve the local Administrators group name
        # on any locale (BUILTIN\Administrators is English-only)
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
        $adminGroup = $adminSid.Translate([System.Security.Principal.NTAccount]).Value
        Write-Log "  Using admin group: $adminGroup" -Level DEBUG
        $principal = New-ScheduledTaskPrincipal -GroupId $adminGroup -RunLevel Highest

        Register-ScheduledTask -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description 'Resumes wfu-tool after reboot' `
            -Force -ErrorAction Stop | Out-Null

        Write-Log "Scheduled task '$taskName' registered -- will resume at next logon." -Level SUCCESS
        $registered = $true
    } catch {
        Write-Log "Could not create scheduled task: $_" -Level WARN
    }

    # --- Fallback: RunOnce registry entry ---
    try {
        $runOnceCmd = "powershell.exe $psArgs"
        Set-ItemProperty $Script:RunOnceKey -Name 'wfu-tool' -Value $runOnceCmd -ErrorAction SilentlyContinue

        if (-not $registered) {
            Write-Log 'Registered RunOnce fallback for resume-after-reboot.' -Level WARN
        } else {
            Write-Log 'RunOnce fallback also registered as backup.' -Level DEBUG
        }
    } catch {
        Write-Log "Could not register RunOnce fallback: $_" -Level WARN
    }

    if (-not $registered) {
        Write-Log 'WARNING: Could not register scheduled task. Resume may depend on RunOnce.' -Level WARN
        Write-Log 'If the script does not auto-resume, re-run launch-wfu-tool.bat manually.' -Level WARN
    }
}

function Clear-ResumeAfterReboot {
    <#
    .SYNOPSIS
        Removes the scheduled task, RunOnce entry, and resume registry state.
        Restores any settings we temporarily changed (like WSUS).
    #>
    # Remove scheduled task
    try {
        Unregister-ScheduledTask -TaskName 'wfu-tool-resume' -Confirm:$false -ErrorAction SilentlyContinue
    } catch { }

    # Remove RunOnce entry
    try {
        Remove-ItemProperty $Script:RunOnceKey -Name 'wfu-tool' -ErrorAction SilentlyContinue
    } catch { }

    # Restore settings and clean up registry state
    try {
        if (Test-Path $Script:ResumeRegKey) {
            # Restore WSUS setting if we disabled it
            $origWsus = Get-RegValue $Script:ResumeRegKey 'OriginalUseWUServer'
            if ($null -ne $origWsus) {
                $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
                Set-RegValue $wuKey 'UseWUServer' $origWsus '' | Out-Null
                Write-Log 'Restored original UseWUServer setting.' -Level DEBUG
            }
            Remove-Item $Script:ResumeRegKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Request-Reboot {
    param([string]$Reason)

    Write-Log '==============================================================='
    Write-Log "  REBOOT REQUIRED: $Reason"
    Write-Log '==============================================================='

    if ($NoReboot) {
        Write-Log 'NoReboot flag is set. Please reboot manually.' -Level WARN
        Write-Log 'The script will auto-resume after reboot via scheduled task.'
        Write-Log 'If it does not, re-run launch-wfu-tool.bat.'
        return
    }

    Write-Log 'System will reboot in 30 seconds. Press Ctrl+C to abort.' -Level WARN
    Write-Log 'The script will resume automatically after reboot.'

    for ($i = 30; $i -gt 0; $i--) {
        Write-Host "`rRebooting in $i seconds... (Ctrl+C to cancel)" -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ''

    try {
        Restart-Computer -Force -ErrorAction Stop
    } catch {
        Write-Log "Restart-Computer failed: $_ -- trying shutdown.exe..." -Level WARN
        try {
            & shutdown.exe /r /t 5 /f /d p:2:4
        } catch {
            Write-Log 'Could not initiate reboot -- please restart manually.' -Level ERROR
        }
    }
}

# =====================================================================
# Region: Pre-flight -- Cumulative Update Check
# =====================================================================

function Update-CumulativePatches {
    Write-Log 'Checking for pending cumulative updates on current version...'

    $result = Invoke-WithRetry -Description 'Cumulative update check' -MaxAttempts 2 -Action {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $searcher = $updateSession.CreateUpdateSearcher()
        $results = $searcher.Search("IsInstalled=0 AND Type='Software' AND IsHidden=0")

        $cumulativeUpdates = @()
        foreach ($u in $results.Updates) {
            if ($u.Title -match 'Cumulative Update' -and $u.Title -notmatch 'Feature update') {
                $cumulativeUpdates += $u
            }
        }

        if ($cumulativeUpdates.Count -eq 0) {
            Write-Log 'System is up to date on cumulative patches.' -Level SUCCESS
            return 'OK'
        }

        Write-Log "Found $($cumulativeUpdates.Count) cumulative update(s) to install first:" -Level WARN
        foreach ($cu in $cumulativeUpdates) {
            Write-Log "  -> $($cu.Title)"
        }

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($cu in $cumulativeUpdates) {
            if (-not $cu.EulaAccepted) { $cu.AcceptEula() }
            $updatesToInstall.Add($cu) | Out-Null
        }

        Write-Log 'Downloading cumulative updates...'
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $dlResult = $downloader.Download()

        if ($dlResult.ResultCode -ne 2) { throw "Download failed with code $($dlResult.ResultCode)" }

        Write-Log 'Installing cumulative updates...'
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        if ($installResult.RebootRequired) {
            Write-Log 'Cumulative updates installed -- reboot required before feature update.' -Level WARN
            return 'RebootNeeded'
        }

        Write-Log 'Cumulative updates installed successfully.' -Level SUCCESS
        return 'OK'
    }

    if ($null -eq $result) {
        Write-Log 'Could not check for cumulative updates -- continuing anyway.' -Level WARN
        return 'OK'
    }
    return $result
}

# =====================================================================
# Region: Main Orchestrator
# =====================================================================

function Start-UpgradeChain {
    Write-Log '==============================================================='
    Write-Log '  wfu-tool Enablement Script v3.0'
    Write-Log '==============================================================='
    Write-Log "Runtime mode     : $(Get-WfuModeLabel -Mode $Script:ResolvedOptions.Mode)"
    Write-Log "Target version  : $TargetVersion"
    Write-Log "Upgrade method  : $(if ($DirectIso) { 'Direct ISO (skip intermediate versions)' } else { 'Sequential (step by step)' })"
    Write-Log "Log file        : $LogPath"
    Write-Log "Download path   : $DownloadPath"
    Write-Log "No-reboot mode  : $NoReboot"
    Write-Log "Max retries     : $MaxRetries"
    Write-Log ''

    # --- Step 1: Detect current version ---
    $Script:CurrentPhase = 'Version detection'
    Write-Phase 'Detecting current Windows version'
    $current = Get-CurrentWindowsVersion
    Complete-Phase
    Write-Log "Current version : $($current.OS) $($current.VersionKey) (Build $($current.FullBuild))"
    Write-Log ''

    if ($current.VersionKey -eq 'Unknown') {
        Write-Log 'Could not determine current Windows version. Build number not recognized.' -Level ERROR
        $null = Save-DiagnosticBundle -Reason 'Version detection failed'
        return
    }

    # --- Step 2: Already at target? ---
    $currentBuild = $current.Build
    $targetBuild  = $Script:VersionMap[$TargetVersion].Build

    if ($currentBuild -ge $targetBuild) {
        Write-Log "System is already at $($current.VersionKey) (build $currentBuild) -- at or past target $TargetVersion. Nothing to do!" -Level SUCCESS
        Clear-ResumeAfterReboot
        return
    }

    # --- Step 3: Pre-flight checks (toggleable) ---
    $isMediaOnlyMode = $Script:ResolvedOptions.Mode -eq 'IsoDownload' -or $Script:ResolvedOptions.Mode -eq 'UsbFromIso'
    if ($isMediaOnlyMode) {
        Write-Log 'Media-only mode selected -- skipping upgrade pre-flight and reboot orchestration.' -Level INFO
        Update-WfuRuntimeCheckpoint -Stage 'preflight skipped (media-only)' -CurrentVersion $current.VersionKey -CurrentStep $current.VersionKey -NextStep $TargetVersion -SelectedSource $PreferredSource
    } else {
        $Script:CurrentPhase = 'Pre-flight checks'
        Write-Phase 'Configuring TLS'
        Repair-TlsConfiguration
        Complete-Phase

        Write-Phase 'Checking for pending reboots'
        if (Test-PendingReboot) {
            Write-Log 'A reboot is pending from a previous operation.' -Level WARN
            if (-not $NoReboot) {
                Set-ResumeAfterReboot -NextTarget $TargetVersion
                Request-Reboot -Reason 'Clearing pending reboot before starting upgrade.'
                return
            } else {
                Write-Log 'Continuing despite pending reboot (NoReboot mode).' -Level WARN
            }
        }

        Complete-Phase

        Write-Phase 'Checking disk space'
        if (-not $SkipDiskCheck) {
            $diskOk = Test-DiskSpace -RequiredGB 15
            if (-not $diskOk) {
                Write-Log 'Insufficient disk space even after cleanup. Free up space and re-run.' -Level ERROR
                $null = Save-DiagnosticBundle -Reason 'Insufficient disk space'
                return
            }
        } else {
            Write-Log 'Disk space check: SKIPPED' -Level WARN
        }

        Complete-Phase

        Write-Phase 'Checking network connectivity'
        if (-not $SkipNetworkCheck) {
            $networkOk = Test-NetworkReadiness
            if (-not $networkOk) {
                Write-Log 'No network connectivity to Windows Update. Check your connection and re-run.' -Level ERROR
                $null = Save-DiagnosticBundle -Reason 'Network unreachable'
                return
            }
        } else {
            Write-Log 'Network check: SKIPPED' -Level WARN
        }

        Complete-Phase

        $Script:CurrentPhase = 'Hardware bypasses'
        Write-Phase 'Applying hardware requirement bypasses'
        if (-not $SkipBypasses) {
            Set-HardwareBypasses
        } else {
            Write-Log 'Hardware bypasses: SKIPPED' -Level WARN
        }
        Complete-Phase

        $Script:CurrentPhase = 'Blocker removal'
        Write-Phase 'Removing upgrade policy blockers'
        if (-not $SkipBlockerRemoval) {
            Remove-UpgradeBlockers
        } else {
            Write-Log 'Blocker removal: SKIPPED' -Level WARN
        }
        Complete-Phase

        $Script:CurrentPhase = 'Component store repair'
        Write-Phase 'Checking component store health'
        if (-not $SkipRepair) {
            $null = Repair-ComponentStore
        } else {
            Write-Log 'Component store repair: SKIPPED' -Level WARN
        }
        Complete-Phase

        $Script:CurrentPhase = 'Cumulative updates'
        Write-Phase 'Checking for cumulative updates'
        if (-not $SkipCumulativeUpdates) {
            $cuStatus = Update-CumulativePatches
            if ($cuStatus -eq 'RebootNeeded') {
                Set-ResumeAfterReboot -NextTarget $TargetVersion
                Request-Reboot -Reason 'Cumulative updates require a reboot before proceeding with feature update.'
                return
            }
        } else {
            Write-Log 'Cumulative updates: SKIPPED' -Level WARN
        }
        Complete-Phase
        Update-WfuRuntimeCheckpoint -Stage 'preflight complete' -CurrentVersion $current.VersionKey -CurrentStep $current.VersionKey -NextStep $TargetVersion -SelectedSource $PreferredSource
    }

    # =================================================================
    # Step 8: Execute upgrade -- Direct ISO or Sequential
    # =================================================================

    # Auto-promote to Direct ISO for cross-generation upgrades (Win10 -> Win11)
    $isWin10Source = ($current.VersionKey -like 'W10_*')
    $isWin11Target = (-not ($TargetVersion -like 'W10_*'))
    if ($isWin10Source -and $isWin11Target -and -not $DirectIso) {
        Write-Log 'Cross-generation upgrade (Windows 10 -> Windows 11) requires Direct ISO method.' -Level WARN
        Write-Log 'Switching to Direct ISO automatically.' -Level WARN
        $DirectIso = $true
    }

    if ($DirectIso) {
        # ---- DIRECT ISO MODE ----
        $Script:CurrentPhase = "Direct ISO upgrade to $TargetVersion"
        Write-Phase "Starting direct ISO upgrade: $($current.VersionKey) -> $TargetVersion"
        # Skip intermediate versions entirely. Download ISO for the target
        # version and run setup.exe in-place to jump directly.
        Write-Log '==============================================================='
        Write-Log "  DIRECT ISO UPGRADE: $($current.VersionKey) -> $TargetVersion"
        Write-Log '==============================================================='
        Write-Log ''

        # Build a synthetic step for the target version
        $directStep = @{
            From        = $current.VersionKey
            To          = $TargetVersion
            Method      = 'FeatureUpdate'
            MinBuild    = $currentBuild
            TargetBuild = $targetBuild
            Description = "Direct ISO upgrade from $($current.VersionKey) to $TargetVersion"
        }

        # Use the MCT/ISO method directly (Method 3 in the fallback chain)
        Write-Log 'Launching ISO-based in-place upgrade...'
        $result = Install-ViaIsoUpgrade -Step $directStep
        if ($result -is [array]) { $result = $result[-1] }

        if ($result -eq $true) {
            if ($Script:ResolvedOptions.Mode -eq 'IsoDownload') {
                Write-Log "$TargetVersion ISO download completed successfully." -Level SUCCESS
                Clear-ResumeAfterReboot
                return
            }
            if ($Script:ResolvedOptions.CreateUsb) {
                Write-Log "$TargetVersion media preparation completed successfully." -Level SUCCESS
                Clear-ResumeAfterReboot
                Write-Log 'UsbFromIso mode completed successfully -- no reboot required.' -Level SUCCESS
                return
            }
            Write-Log "$TargetVersion direct upgrade initiated successfully." -Level SUCCESS
            Set-ResumeAfterReboot -NextTarget $TargetVersion
            Request-Reboot -Reason "Direct upgrade to $TargetVersion needs a reboot to finalize."
            return
        }

        # ISO failed -- check fallback policy
        if (-not $AllowFallback) {
            Write-Log '' -Level ERROR
            Write-Log '===============================================================' -Level ERROR
            Write-Log '  DIRECT ISO UPGRADE FAILED -- OPERATION ABORTED' -Level ERROR
            Write-Log '===============================================================' -Level ERROR
            Write-Log "  Could not download or apply ISO for $TargetVersion." -Level ERROR
            Write-Log '  Fallback to other methods is DISABLED (default).' -Level ERROR
            Write-Log '' -Level WARN
            Write-Log '  To allow fallback methods, re-run with -AllowFallback' -Level WARN
            Write-Log "  Or place an ISO manually at: $DownloadPath\Windows11.iso" -Level WARN
            $null = Save-DiagnosticBundle -Reason "Direct ISO to $TargetVersion failed, fallback disabled"
            return
        }

        Write-Log 'ISO method failed -- -AllowFallback is enabled, trying alternatives...' -Level WARN

        if (-not $SkipAssistant) {
            $assistResult = $null
            $assistResult = Invoke-WithRetry -Description 'Installation Assistant' -Action {
                return Install-ViaInstallationAssistant -Step $directStep
            }
            if ($assistResult -is [array]) { $assistResult = $assistResult[-1] }

            if ($assistResult -eq $true) {
                if ($Script:ResolvedOptions.Mode -eq 'IsoDownload') {
                    Write-Log "$TargetVersion ISO download completed successfully." -Level SUCCESS
                    Clear-ResumeAfterReboot
                    return
                }
                if ($Script:ResolvedOptions.CreateUsb) {
                    Write-Log "$TargetVersion media preparation completed successfully." -Level SUCCESS
                    Clear-ResumeAfterReboot
                    Write-Log 'UsbFromIso mode completed successfully -- no reboot required.' -Level SUCCESS
                    return
                }
                Write-Log "$TargetVersion upgrade initiated via Installation Assistant." -Level SUCCESS
                Set-ResumeAfterReboot -NextTarget $TargetVersion
                Request-Reboot -Reason "Upgrade to $TargetVersion needs a reboot to finalize."
                return
            }
        } else {
            Write-Log '  Installation Assistant: SKIPPED (disabled)' -Level DEBUG
        }

        # All direct methods failed -- fall through to sequential only if allowed
        Write-Log "Direct upgrade to $TargetVersion failed." -Level ERROR
        Write-Log 'Falling back to sequential mode...' -Level WARN
        Write-Log ''
        # Fall through to sequential mode below
    }

    # ---- SEQUENTIAL MODE ----
    $Script:CurrentPhase = 'Sequential upgrade'
    $remainingSteps = @($Script:UpgradeChain | Where-Object {
        $Script:VersionMap[$_.To].Build -gt $currentBuild -and
        $Script:VersionMap[$_.To].Build -le $targetBuild
    })

    if ($remainingSteps.Count -eq 0) {
        Write-Log 'No upgrade steps needed -- system is up to date.' -Level SUCCESS
        Clear-ResumeAfterReboot
        return
    }

    Write-Log "Upgrade path: $($current.VersionKey) -> $( ($remainingSteps | ForEach-Object { $_.To }) -join ' -> ' )"
    Write-Log ''

    foreach ($step in $remainingSteps) {
        Write-Log '---------------------------------------------------------------'
        Write-Log "STEP: $($step.From) -> $($step.To)  [$($step.Method)]"
        Write-Log '---------------------------------------------------------------'
        $Script:CurrentPhase = "Sequential: $($step.From) -> $($step.To) ($($step.Method))"

        $success = $false
        try {
            $result = $null
            switch ($step.Method) {
                'EnablementPackage' {
                    $result = Install-EnablementPackage -Step $step
                }
                'FeatureUpdate' {
                    $result = Install-FeatureUpdate -Step $step
                }
            }
            if ($result -is [array]) { $result = $result[-1] }
            $success = ($result -eq $true)
        } catch {
            Write-Log "Unexpected error during $($step.Method): $_" -Level ERROR
            Write-Log $_.ScriptStackTrace -Level DEBUG
            $success = $false
        }

        if ($success) {
            if ($Script:ResolvedOptions.Mode -eq 'IsoDownload') {
                Write-Log "$($step.To) ISO download completed successfully." -Level SUCCESS
                Clear-ResumeAfterReboot
                return
            }
            if ($Script:ResolvedOptions.CreateUsb) {
                Write-Log "$($step.To) media preparation completed successfully." -Level SUCCESS
                Clear-ResumeAfterReboot
                Write-Log 'UsbFromIso mode completed successfully -- no reboot required.' -Level SUCCESS
                return
            }
            Write-Log "$($step.To) upgrade initiated successfully." -Level SUCCESS

            $nextSteps = @($remainingSteps | Where-Object { $Script:VersionMap[$_.To].Build -gt $Script:VersionMap[$step.To].Build })
            if ($nextSteps.Count -gt 0) {
                Set-ResumeAfterReboot -NextTarget ($nextSteps | Select-Object -First 1).To
            } else {
                Clear-ResumeAfterReboot
            }
            Request-Reboot -Reason "Feature upgrade to $($step.To) needs a reboot to finalize."
            return
        } else {
            Write-Log "Upgrade to $($step.To) could not be completed automatically." -Level ERROR
            Write-Log 'Please complete this step manually, reboot, and re-run the script.' -Level WARN
            Set-ResumeAfterReboot -NextTarget $step.To
            return
        }
    }

    # All steps done
    Clear-ResumeAfterReboot
    Write-Log '===============================================================' -Level SUCCESS
    Write-Log "  All upgrades complete! System is now at $TargetVersion." -Level SUCCESS
    Write-Log '===============================================================' -Level SUCCESS
}

# =====================================================================
# Region: Entry Point
# =====================================================================

# =====================================================================
# Region: Ctrl+C / Cancellation Handler
# =====================================================================

# Register handler for Ctrl+C (CancelKeyPress) to log gracefully
$Script:CancelHandler = $null
try {
    $Script:CancelHandler = [Console]::add_CancelKeyPress({
        param($sender, $eventArgs)
        $eventArgs.Cancel = $true  # Prevent immediate termination -- let finally run
        $Script:Cancelled = $true
        Write-Host '' -ForegroundColor Red
        Write-Host '  *** CTRL+C DETECTED -- Cancelling...' -ForegroundColor Red
        Write-Host "  *** Phase at cancellation: $($Script:CurrentPhase)" -ForegroundColor Red
        Write-Host '  *** Cleaning up -- do NOT close this window...' -ForegroundColor Yellow
    })
} catch {
    # CancelKeyPress may not be available in all hosts (e.g. ISE)
}

# =====================================================================
# Region: Entry Point
# =====================================================================

# Resolve automation/config/session state before anything else uses the legacy globals.
try {
    $resolvedOptions = Initialize-WfuRuntimeOptions -BoundParameters $PSBoundParameters
    Apply-WfuRuntimeOptions -Options $resolvedOptions
    Write-Log "Runtime mode resolved: $($Script:ResolvedOptions.Mode)" -Level DEBUG
    Write-Log "Checkpoint path: $($Script:ResolvedOptions.CheckpointPath)" -Level DEBUG
    if ($Script:CheckpointState -and $Script:CheckpointState.Stage) {
        Write-Log "Loaded checkpoint stage: $($Script:CheckpointState.Stage)" -Level INFO
    }
    Update-WfuRuntimeCheckpoint -Stage 'initialized' -CurrentVersion $null -CurrentStep $TargetVersion -NextStep $TargetVersion -SelectedSource $PreferredSource
} catch {
    Write-Host "ERROR: Failed to resolve runtime options: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create download directory
try {
    if (-not (Test-Path $Script:DownloadPath)) {
        New-Item -ItemType Directory -Path $Script:DownloadPath -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $Script:DownloadPath = Join-Path $env:TEMP 'wfu-tool'
    New-Item -ItemType Directory -Path $Script:DownloadPath -Force -ErrorAction SilentlyContinue | Out-Null
    if ($Script:ResolvedOptions) {
        $Script:ResolvedOptions.DownloadPath = $Script:DownloadPath
        if ($Script:ResolvedOptions.SessionId) {
            $Script:ResolvedOptions.CheckpointPath = Get-WfuCheckpointPath -DownloadPath $Script:DownloadPath -SessionId $Script:ResolvedOptions.SessionId
        }
    }
    Write-Log "Could not create download path, using: $Script:DownloadPath" -Level WARN
}

# Run the chain with comprehensive error + cancellation handling
$exitReason = 'Completed normally'
try {
    if ($env:WFU_TOOL_TEST_MODE -eq '1') {
        Write-Log 'WFU_TOOL_TEST_MODE detected -- skipping upgrade execution.' -Level DEBUG
        $exitReason = 'Test mode'
    } else {
        Start-UpgradeChain
    }

    if ($Script:Cancelled) {
        $exitReason = "Cancelled by user (Ctrl+C) during: $($Script:CurrentPhase)"
    }
} catch {
    if ($Script:Cancelled) {
        $exitReason = "Cancelled by user (Ctrl+C) during: $($Script:CurrentPhase)"
    } else {
        $exitReason = "Fatal error: $_"
        Write-Log "FATAL UNHANDLED ERROR: $_" -Level ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
} finally {
    # ================================================================
    # This ALWAYS runs -- even on Ctrl+C, pipeline stops, or exceptions.
    # Log final state and warn about potential inconsistencies.
    # ================================================================

    $runtime = [math]::Round(((Get-Date) - $Script:StartTime).TotalSeconds)

    Write-Log ''
    Write-Log '==============================================================='
    Write-Log '  SESSION SUMMARY'
    Write-Log '==============================================================='
    Write-Log "  Exit reason    : $exitReason"
    Write-Log "  Last phase     : $($Script:CurrentPhase)"
    Write-Log "  Runtime        : ${runtime}s"
    Write-Log "  Errors logged  : $($Script:ErrorLog.Count)"
    Write-Log "  Log file       : $LogPath"

    # Warn about inconsistent state based on what phase was interrupted
    if ($Script:Cancelled -or $exitReason -match 'Fatal') {
        Write-Log '' -Level WARN
        Write-Log '  WARNING: SCRIPT DID NOT COMPLETE NORMALLY' -Level ERROR

        # Phase-specific inconsistency warnings
        $phase = $Script:CurrentPhase
        $warnings = @()

        if ($phase -match 'Hardware bypasses') {
            $warnings += 'Registry bypass patches may be partially applied.'
            $warnings += 'Some hardware checks may be bypassed while others are not.'
            $warnings += 'Re-run the script to complete, or check HKLM\SYSTEM\Setup\LabConfig and HKLM\...\HwReqChk manually.'
        }
        if ($phase -match 'Blocker removal') {
            $warnings += 'Upgrade policy blockers may be partially removed.'
            $warnings += 'WSUS UseWUServer may have been disabled without being restored.'
            $warnings += 'Check HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate for state.'
        }
        if ($phase -match 'Telemetry') {
            $warnings += 'Telemetry settings may be partially applied.'
            $warnings += 'DiagTrack/dmwappushservice may be stopped but not fully disabled.'
        }
        if ($phase -match 'Component store') {
            $warnings += 'DISM /RestoreHealth or SFC may have been interrupted mid-repair.'
            $warnings += 'Run "DISM /Online /Cleanup-Image /RestoreHealth" manually if needed.'
        }
        if ($phase -match 'Cumulative updates') {
            $warnings += 'Cumulative updates may be partially downloaded or installed.'
            $warnings += 'Check Windows Update for pending operations.'
        }
        if ($phase -match 'Direct ISO|ISO download|ESD') {
            $warnings += 'ISO/ESD download may be incomplete -- partial files in download directory.'
            $warnings += "Check $DownloadPath for incomplete .iso or .esd files."
            $warnings += 'Delete partial files before re-running.'
        }
        if ($phase -match 'setup\.exe|Install-ViaMedia|appraiserres|hwreqchk') {
            $warnings += 'Setup.exe may have been launched but interrupted.'
            $warnings += 'Check if $WINDOWS.~BT folder exists -- setup may be in progress.'
            $warnings += 'If setup started, a reboot may still be pending.'
            $warnings += 'Mounted ISO may still be attached -- check disk management.'
        }
        if ($phase -match 'Installation Assistant|IFEO|SetupHost') {
            $warnings += 'The Installation Assistant may still be running in the background.'
            $warnings += 'IFEO hook on SetupHost.exe may still be registered.'
            $warnings += 'Check Task Manager for Windows11InstallationAssistant.exe.'
            $warnings += 'Run: reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SetupHost.exe" /f'
        }
        if ($phase -match 'Sequential') {
            $warnings += 'A sequential upgrade step may have been interrupted.'
            $warnings += 'The resume-after-reboot task may be registered for a step that did not complete.'
            $warnings += 'Re-run the script to retry from the current version.'
        }

        if ($warnings.Count -eq 0) {
            $warnings += 'Script was interrupted. Some operations may be incomplete.'
            $warnings += 'Re-run the script to continue from where it left off.'
        }

        Write-Log '' -Level WARN
        Write-Log '  POTENTIAL INCONSISTENCIES:' -Level WARN
        foreach ($w in $warnings) {
            Write-Log "    - $w" -Level WARN
        }

        Write-Log '' -Level WARN
        Write-Log '  RECOMMENDED ACTIONS:' -Level WARN
        Write-Log '    1. Review the log file for what completed before interruption.' -Level WARN
        Write-Log '    2. Re-run launch-wfu-tool.bat to retry -- it will pick up from current state.' -Level WARN
        Write-Log '    3. If setup.exe was running, check Task Manager and reboot if needed.' -Level WARN

        # Capture diagnostics on abnormal exit
        try {
            $null = Save-DiagnosticBundle -Reason $exitReason
        } catch { }
    }

    Write-Log '==============================================================='

    # Unregister Ctrl+C handler
    try {
        if ($Script:CancelHandler) {
            [Console]::remove_CancelKeyPress($Script:CancelHandler)
        }
    } catch { }
}
