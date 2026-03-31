<#
.SYNOPSIS
    Interactive terminal UI for wfu-tool.
    Handles system info display, version detection, target selection,
    step configuration, and launches the main upgrade engine.
#>
param(
    [string]$ScriptRoot = $PSScriptRoot,
    [Alias('?')]
    [switch]$Help,
    [string]$ConfigPath,
    [ValidateSet('Interactive', 'IsoDownload', 'UsbFromIso', 'AutomatedUpgrade', 'Resume', 'Headless', 'CreateUsb', 'createusb', 'create_usb')]
    [string]$Mode = 'Interactive',
    [switch]$Interactive,
    [switch]$Headless,
    [switch]$CreateUsb,
    [string]$UsbDiskNumber,
    [string]$UsbDiskId,
    [switch]$KeepIso,
    [string]$PreferredSource,
    [string]$ForceSource,
    [switch]$AllowDeadSources,
    [string]$CheckpointPath,
    [string]$SessionId,
    [switch]$ResumeFromCheckpoint,
    [string]$TargetVersion,
    [string]$LogPath,
    [string]$DownloadPath,
    [switch]$NoReboot,
    [switch]$ForceOnlineUpdate,
    [int]$MaxRetries = 2,
    [switch]$DirectIso,
    [switch]$AllowFallback,
    [switch]$SkipBypasses,
    [switch]$SkipBlockerRemoval,
    [switch]$SkipTelemetry,
    [switch]$SkipRepair,
    [switch]$SkipCumulativeUpdates,
    [switch]$SkipNetworkCheck,
    [switch]$SkipDiskCheck,
    [switch]$SkipDirectEsd,
    [switch]$SkipEsd,
    [switch]$SkipFido,
    [switch]$SkipMct,
    [switch]$SkipAssistant,
    [switch]$SkipWindowsUpdate
)

function Show-WfuLauncherHelp {
    Write-Host ''
    Write-Host 'launch-wfu-tool' -ForegroundColor Cyan
    Write-Host 'Usage: .\launch-wfu-tool.ps1 [options]' -ForegroundColor White
    Write-Host ''
    Write-Host 'This is the interactive/front-door launcher for wfu-tool.' -ForegroundColor DarkGray
    Write-Host 'It can open the TUI, run headless, create USB media, or load an INI config.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Common options:' -ForegroundColor Cyan
    Write-Host '  -Help                         Show this help text'
    Write-Host '  -Interactive                  Force interactive mode'
    Write-Host '  -Headless                     Force headless mode'
    Write-Host '  -Mode <mode>                  Interactive, Headless, Resume, CreateUsb, IsoDownload, UsbFromIso, AutomatedUpgrade'
    Write-Host '  -ConfigPath <path>            Load an INI config file'
    Write-Host '  -TargetVersion <version>      Example: W10_22H2, 24H2, 25H2'
    Write-Host '  -CheckpointPath <path>        Use a specific checkpoint'
    Write-Host '  -ResumeFromCheckpoint         Resume from checkpoint state'
    Write-Host ''
    Write-Host 'Media and USB:' -ForegroundColor Cyan
    Write-Host '  -CreateUsb                    Build USB media'
    Write-Host '  -UsbDiskNumber <n>            Target USB disk number'
    Write-Host '  -UsbDiskId <id>               Target USB disk unique ID'
    Write-Host '  -KeepIso                      Keep ISO after USB creation'
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Cyan
    Write-Host '  .\launch-wfu-tool.ps1'
    Write-Host '  .\launch-wfu-tool.ps1 -Headless -ConfigPath .\configs\job.ini'
    Write-Host '  .\launch-wfu-tool.ps1 -Mode CreateUsb -TargetVersion 25H2 -UsbDiskNumber 3'
    Write-Host ''
}

if ($Help) {
    Show-WfuLauncherHelp
    return
}

# Verify admin -- works whether dot-sourced or run via -File
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "  Double-click launch-wfu-tool.bat instead." -ForegroundColor Yellow
    return
}

# If ScriptRoot is empty (dot-sourced), fall back to current directory
if ([string]::IsNullOrEmpty($ScriptRoot)) { $ScriptRoot = $PWD.Path }

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'wfu-tool'

# Load the shared automation/config helpers if present.
$automationScript = Join-Path $ScriptRoot 'modules\Upgrade\Automation.ps1'
if (Test-Path $automationScript) {
    . $automationScript
}

# Load the Windows Update client for remote version discovery.
$wuClientScript = Join-Path $ScriptRoot 'wfu-tool-windows-update.ps1'
if (Test-Path $wuClientScript) {
    . $wuClientScript
}

# ---------------------------------------------
# Region: Console Window Setup
# ---------------------------------------------

try {
    $console = $Host.UI.RawUI

    Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ScreenInfo {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int W, int H, bool repaint);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@

    $screenW = [ScreenInfo]::GetSystemMetrics(0)
    $screenH = [ScreenInfo]::GetSystemMetrics(1)
    $charHeight = 18
    $taskbarHeight = 48
    $usableH = $screenH - $taskbarHeight
    $maxRows = [math]::Floor($usableH / $charHeight)
    if ($maxRows -lt 30) { $maxRows = 30 }
    if ($maxRows -gt 80) { $maxRows = 80 }
    $cols = 120

    $bufferSize = New-Object System.Management.Automation.Host.Size($cols, 9999)
    $console.BufferSize = $bufferSize
    $windowSize = New-Object System.Management.Automation.Host.Size($cols, $maxRows)
    $console.WindowSize = $windowSize

    $hwnd = [ScreenInfo]::GetForegroundWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        $rect = New-Object ScreenInfo+RECT
        [void][ScreenInfo]::GetWindowRect($hwnd, [ref]$rect)
        $winW = $rect.R - $rect.L
        $newX = [math]::Max(0, [math]::Floor(($screenW - $winW) / 2))
        $newY = 0
        [void][ScreenInfo]::MoveWindow($hwnd, $newX, $newY, $winW, $usableH, $true)
    }
}
catch {
    try { & mode.com con: cols=120 lines=50 } catch { }
}

# ---------------------------------------------
# Region: Terminal Helpers
# ---------------------------------------------

function Write-Color {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'White',
        [switch]$NoNewLine
    )
    $prev = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    if ($NoNewLine) { Write-Host $Text -NoNewline }
    else { Write-Host $Text }
    $Host.UI.RawUI.ForegroundColor = $prev
}

function Write-Header {
    param([string]$Title)
    $line = [string]::new([char]0x2550, 70)
    Write-Host ""
    Write-Color "  $line" Cyan
    Write-Color "  $Title" White
    Write-Color "  $line" Cyan
    Write-Host ""
}

function Write-InfoLine {
    param([string]$Label, [string]$Value, [ConsoleColor]$ValueColor = 'White')
    Write-Color "    $($Label.PadRight(22))" DarkGray -NoNewLine
    Write-Color $Value $ValueColor
}

function Write-Separator {
    Write-Color "  $([string]::new([char]0x2500, 70))" DarkGray
}

function Show-Spinner {
    param([string]$Message, [int]$Seconds = 2)
    $spinChars = @('|', '/', '-', '\')
    $end = (Get-Date).AddSeconds($Seconds)
    $i = 0
    while ((Get-Date) -lt $end) {
        Write-Host "`r    $($spinChars[$i % 4]) $Message" -NoNewline
        Start-Sleep -Milliseconds 120
        $i++
    }
    Write-Host "`r    $([char]0x2713) $Message" -ForegroundColor Green
}

function Show-ToggleMenu {
    <#
    .SYNOPSIS
        Displays a toggleable checklist menu. User presses number keys to toggle
        items on/off, Enter to confirm. Returns the items array with .Enabled updated.
    #>
    param(
        [array]$Items,    # Array of @{ Name; Description; Enabled }
        [string]$Title = 'Configure Options'
    )

    Write-Header $Title

    $done = $false
    while (-not $done) {
        # Render current state
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $check = if ($item.Enabled) { '[X]' } else { '[ ]' }
            $color = if ($item.Enabled) { 'Green' } else { 'DarkGray' }
            Write-Color "    " White -NoNewLine
            Write-Color "$($i + 1) " Yellow -NoNewLine
            Write-Color "$check " $color -NoNewLine
            Write-Color "$($item.Name)" $color -NoNewLine
            if ($item.Description) {
                Write-Color "  $($item.Description)" DarkGray
            }
            else {
                Write-Host ""
            }
        }
        Write-Host ""
        Write-Color "    Toggle: type number(s) | " DarkGray -NoNewLine
        Write-Color "A" Yellow -NoNewLine
        Write-Color "=all on | " DarkGray -NoNewLine
        Write-Color "N" Yellow -NoNewLine
        Write-Color "=all off | " DarkGray -NoNewLine
        Write-Color "Enter" Yellow -NoNewLine
        Write-Color "=confirm" DarkGray
        Write-Color "    > " Yellow -NoNewLine
        $key = Read-Host

        if ([string]::IsNullOrWhiteSpace($key)) {
            $done = $true
        }
        elseif ($key -match '^[aA]$') {
            foreach ($item in $Items) { $item.Enabled = $true }
            Write-Host ""
        }
        elseif ($key -match '^[nN]$') {
            foreach ($item in $Items) { $item.Enabled = $false }
            Write-Host ""
        }
        else {
            # Parse number(s) -- supports "1", "13", "1 3", "1,3"
            $nums = [regex]::Matches($key, '\d+') | ForEach-Object { [int]$_.Value }
            foreach ($n in $nums) {
                if ($n -ge 1 -and $n -le $Items.Count) {
                    $Items[$n - 1].Enabled = -not $Items[$n - 1].Enabled
                }
            }
            Write-Host ""
        }
    }
    return $Items
}

function Read-ConfigSavePath {
    param(
        [string]$DefaultPath
    )

    Write-Color "    Config path (default: $DefaultPath): " Yellow -NoNewLine
    $value = Read-Host
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultPath
    }
    return $value.Trim()
}

function Normalize-LauncherMode {
    param([string]$Mode)

    if (-not $Mode) { return 'Interactive' }

    switch ($Mode.Trim().ToLowerInvariant()) {
        'interactive' { return 'Interactive' }
        'isodownload' { return 'IsoDownload' }
        'usbfromiso' { return 'UsbFromIso' }
        'automatedupgrade' { return 'AutomatedUpgrade' }
        'resume' { return 'Resume' }
        'headless' { return 'AutomatedUpgrade' }
        'createusb' { return 'UsbFromIso' }
        'create_usb' { return 'UsbFromIso' }
        default { return 'Interactive' }
    }
}

function Get-LauncherModeChoices {
    @(
        [pscustomobject]@{
            Id          = 'Interactive'
            Label       = 'Interactive'
            Description = 'guided prompts, current behavior'
        }
        [pscustomobject]@{
            Id          = 'IsoDownload'
            Label       = 'Just download ISO'
            Description = 'download or reuse an ISO and stop after media acquisition'
        }
        [pscustomobject]@{
            Id          = 'UsbFromIso'
            Label       = 'Download/use ISO and make USB drive'
            Description = 'reuse an existing ISO or download one, then write bootable USB media'
        }
        [pscustomobject]@{
            Id          = 'AutomatedUpgrade'
            Label       = 'Automated in-place upgrade'
            Description = 'unattended upgrade flow'
        }
    )
}

function Select-LauncherMode {
    param([string]$DefaultMode)

    $choices = Get-LauncherModeChoices
    $normalizedDefault = Normalize-LauncherMode -Mode $DefaultMode
    $defaultIndex = [Math]::Max(1, ([array]::IndexOf(@($choices.Id), $normalizedDefault) + 1))

    Write-Header 'SELECT OPERATION MODE'
    for ($i = 0; $i -lt $choices.Count; $i++) {
        $choice = $choices[$i]
        Write-Color "    [$($i + 1)]  $($choice.Label)" White
        Write-Color "         $($choice.Description)" DarkGray
    }
    Write-Color "    [0]  Cancel / Exit" DarkGray
    Write-Host ''

    while ($true) {
        Write-Color "    Select mode [1-$($choices.Count)] (default: $defaultIndex): " Yellow -NoNewLine
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) {
            return $choices[$defaultIndex - 1].Id
        }
        elseif ($input -eq '0') {
            return $null
        }
        elseif ($input -match '^[1-4]$') {
            return $choices[[int]$input - 1].Id
        }
        else {
            Write-Color '    Invalid selection. Try again.' Red
        }
    }
}

function Get-LauncherUsbDiskCandidates {
    $candidates = @()
    try {
        $candidates = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object {
                $_ -and $_.BusType -and $_.BusType -match 'USB|SD' -and -not $_.IsBoot -and -not $_.IsSystem
            } | Sort-Object Number)
    }
    catch {
        $candidates = @()
    }
    return $candidates
}

function Select-LauncherUsbDisk {
    param(
        [string]$DefaultDiskNumber,
        [string]$DefaultDiskId
    )

    if ($DefaultDiskNumber -or $DefaultDiskId) {
        return @{
            UsbDiskNumber = $DefaultDiskNumber
            UsbDiskId     = $DefaultDiskId
        }
    }

    $candidates = Get-LauncherUsbDiskCandidates
    Write-Header 'SELECT USB TARGET DISK'

    if ($candidates.Count -gt 0) {
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $disk = $candidates[$i]
            $sizeGb = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 1) } else { 0 }
            $friendly = @($disk.FriendlyName, $disk.Model) | Where-Object { $_ } | Select-Object -First 1
            Write-Color "    [$($i + 1)]  Disk $($disk.Number)  $sizeGb GB  $friendly" White
        }
        Write-Color "    [M]  Enter disk number manually" DarkGray
    }
    else {
        Write-Color "    No obvious USB disks were detected." Yellow
    }
    Write-Color "    [0]  Cancel / Exit" DarkGray
    Write-Host ''

    while ($true) {
        Write-Color "    Select disk number: " Yellow -NoNewLine
        $selection = Read-Host
        if ([string]::IsNullOrWhiteSpace($selection) -and $candidates.Count -gt 0) {
            return @{
                UsbDiskNumber = [string]$candidates[0].Number
                UsbDiskId     = $null
            }
        }
        elseif ($selection -eq '0') {
            return $null
        }
        elseif ($selection -match '^[1-9]\d*$' -and [int]$selection -le $candidates.Count) {
            $disk = $candidates[[int]$selection - 1]
            return @{
                UsbDiskNumber = [string]$disk.Number
                UsbDiskId     = $null
            }
        }
        elseif ($selection -match '^\d+$') {
            return @{
                UsbDiskNumber = $selection
                UsbDiskId     = $null
            }
        }
        elseif ($selection -match '^[mM]$') {
            Write-Color "    Enter disk number: " Yellow -NoNewLine
            $manual = Read-Host
            if ($manual -match '^\d+$') {
                return @{
                    UsbDiskNumber = $manual
                    UsbDiskId     = $null
                }
            }
        }
        else {
            Write-Color '    Invalid selection. Try again.' Red
        }
    }
}

function New-LauncherMinimalIniLines {
    @(
        '; wfu-tool default config template'
        '; This file starts with interactive mode and no overrides.'
        '[general]'
        'mode=interactive'
        ''
        '[checks]'
        '; add overrides here when needed'
        ''
        '[sources]'
        '; add overrides here when needed'
        ''
        '[usb]'
        '; add overrides here when needed'
        ''
        '[resume]'
        '; add overrides here when needed'
    )
}

function Save-LauncherDefaultIniConfig {
    param([string]$Path)

    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -Path $Path -Value (New-LauncherMinimalIniLines) -Encoding UTF8
    return $Path
}

function Get-LauncherRuntimeMode {
    param([string]$Mode)

    switch (Normalize-LauncherMode -Mode $Mode) {
        'AutomatedUpgrade' { return 'Headless' }
        'UsbFromIso' { return 'CreateUsb' }
        default { return 'Interactive' }
    }
}

function New-LauncherConfigOptions {
    param(
        [string]$Mode,
        [string]$TargetVersion,
        [string]$LogPath,
        [string]$DownloadPath,
        [bool]$NoReboot,
        [bool]$DirectIso,
        [bool]$AllowFallback,
        [bool]$ForceOnlineUpdate,
        [int]$MaxRetries,
        [bool]$SkipBypasses,
        [bool]$SkipBlockerRemoval,
        [bool]$SkipTelemetry,
        [bool]$SkipRepair,
        [bool]$SkipCumulativeUpdates,
        [bool]$SkipNetworkCheck,
        [bool]$SkipDiskCheck,
        [bool]$SkipDirectEsd,
        [bool]$SkipEsd,
        [bool]$SkipFido,
        [bool]$SkipMct,
        [bool]$SkipAssistant,
        [bool]$SkipWindowsUpdate,
        [bool]$CreateUsb,
        [string]$UsbDiskNumber,
        [string]$UsbDiskId,
        [bool]$KeepIso,
        [string]$PreferredSource,
        [string]$ForceSource,
        [bool]$AllowDeadSources,
        [string]$CheckpointPath,
        [string]$SessionId,
        [bool]$ResumeFromCheckpoint,
        [hashtable]$SourceHealth
    )

    $normalizedMode = Normalize-LauncherMode -Mode $Mode
    [ordered]@{
        Mode                  = $normalizedMode
        TargetVersion         = $TargetVersion
        LogPath               = $LogPath
        DownloadPath          = $DownloadPath
        NoReboot              = $NoReboot
        DirectIso             = $DirectIso
        AllowFallback         = $AllowFallback
        ForceOnlineUpdate     = $ForceOnlineUpdate
        MaxRetries            = $MaxRetries
        SkipBypasses          = $SkipBypasses
        SkipBlockerRemoval    = $SkipBlockerRemoval
        SkipTelemetry         = $SkipTelemetry
        SkipRepair            = $SkipRepair
        SkipCumulativeUpdates = $SkipCumulativeUpdates
        SkipNetworkCheck      = $SkipNetworkCheck
        SkipDiskCheck         = $SkipDiskCheck
        SkipDirectEsd         = $SkipDirectEsd
        SkipEsd               = $SkipEsd
        SkipFido              = $SkipFido
        SkipMct               = $SkipMct
        SkipAssistant         = $SkipAssistant
        SkipWindowsUpdate     = $SkipWindowsUpdate
        CreateUsb             = $CreateUsb -or ($normalizedMode -eq 'UsbFromIso')
        UsbDiskNumber         = $UsbDiskNumber
        UsbDiskId             = $UsbDiskId
        KeepIso               = $KeepIso
        UsbPartitionStyle     = 'gpt'
        PreferredSource       = $PreferredSource
        ForceSource           = $ForceSource
        AllowDeadSources      = $AllowDeadSources
        CheckpointPath        = $CheckpointPath
        SessionId             = $SessionId
        ResumeFromCheckpoint  = $ResumeFromCheckpoint
        ResumeEnabled         = $true
        SourceHealth          = if ($SourceHealth) { $SourceHealth } else { [ordered]@{} }
    }
}

function Get-LauncherCurrentValues {
    param(
        [string]$ScriptRoot,
        [string]$Mode,
        [switch]$Interactive,
        [switch]$Headless,
        [switch]$CreateUsb,
        [string]$UsbDiskNumber,
        [string]$UsbDiskId,
        [switch]$KeepIso,
        [string]$PreferredSource,
        [string]$ForceSource,
        [switch]$AllowDeadSources,
        [string]$CheckpointPath,
        [string]$SessionId,
        [switch]$ResumeFromCheckpoint,
        [string]$TargetVersion,
        [string]$LogPath,
        [string]$DownloadPath,
        [switch]$NoReboot,
        [switch]$ForceOnlineUpdate,
        [int]$MaxRetries,
        [switch]$DirectIso,
        [switch]$AllowFallback,
        [switch]$SkipBypasses,
        [switch]$SkipBlockerRemoval,
        [switch]$SkipTelemetry,
        [switch]$SkipRepair,
        [switch]$SkipCumulativeUpdates,
        [switch]$SkipNetworkCheck,
        [switch]$SkipDiskCheck,
        [switch]$SkipDirectEsd,
        [switch]$SkipEsd,
        [switch]$SkipFido,
        [switch]$SkipMct,
        [switch]$SkipAssistant,
        [switch]$SkipWindowsUpdate
    )

    $normalizedMode = Normalize-LauncherMode -Mode $Mode
    if ($normalizedMode -eq 'Interactive') {
        if ($CreateUsb) {
            $normalizedMode = 'UsbFromIso'
        }
        elseif ($Headless) {
            $normalizedMode = 'AutomatedUpgrade'
        }
    }

    [ordered]@{
        ScriptRoot            = $ScriptRoot
        Mode                  = $normalizedMode
        Interactive           = [bool]$Interactive
        Headless              = [bool]$Headless
        CreateUsb             = [bool]$CreateUsb
        UsbDiskNumber         = $UsbDiskNumber
        UsbDiskId             = $UsbDiskId
        KeepIso               = [bool]$KeepIso
        PreferredSource       = $PreferredSource
        ForceSource           = $ForceSource
        AllowDeadSources      = [bool]$AllowDeadSources
        CheckpointPath        = $CheckpointPath
        SessionId             = $SessionId
        ResumeFromCheckpoint  = [bool]$ResumeFromCheckpoint
        TargetVersion         = $TargetVersion
        LogPath               = $LogPath
        DownloadPath          = $DownloadPath
        NoReboot              = [bool]$NoReboot
        ForceOnlineUpdate     = [bool]$ForceOnlineUpdate
        MaxRetries            = $MaxRetries
        DirectIso             = [bool]$DirectIso
        AllowFallback         = [bool]$AllowFallback
        SkipBypasses          = [bool]$SkipBypasses
        SkipBlockerRemoval    = [bool]$SkipBlockerRemoval
        SkipTelemetry         = [bool]$SkipTelemetry
        SkipRepair            = [bool]$SkipRepair
        SkipCumulativeUpdates = [bool]$SkipCumulativeUpdates
        SkipNetworkCheck      = [bool]$SkipNetworkCheck
        SkipDiskCheck         = [bool]$SkipDiskCheck
        SkipDirectEsd         = [bool]$SkipDirectEsd
        SkipEsd               = [bool]$SkipEsd
        SkipFido              = [bool]$SkipFido
        SkipMct               = [bool]$SkipMct
        SkipAssistant         = [bool]$SkipAssistant
        SkipWindowsUpdate     = [bool]$SkipWindowsUpdate
    }
}

function Get-SourceHealthLabel {
    param(
        [string]$SourceId,
        [hashtable]$HealthMap
    )

    if (-not (Get-Command Get-WfuSourceHealth -ErrorAction SilentlyContinue)) {
        return ''
    }

    $health = Get-WfuSourceHealth -SourceId $SourceId -HealthMap $HealthMap
    switch ($health) {
        'dead' { return ' [dead]' }
        'degraded' { return ' [degraded]' }
        'unknown' { return ' [unknown]' }
        default { return '' }
    }
}

function Select-WfuTargetVersion {
    param(
        [string]$CurrentVersionKey,
        [string[]]$AvailableTargets,
        [string]$PresetTarget,
        [switch]$AllowPrompt
    )

    if (-not $AvailableTargets -or $AvailableTargets.Count -eq 0) {
        return $null
    }

    if ($PresetTarget -and ($AvailableTargets -contains $PresetTarget)) {
        return $PresetTarget
    }

    if (-not $AllowPrompt) {
        return $AvailableTargets[-1]
    }

    $families = Get-WfuTargetFamilies -AvailableTargets $AvailableTargets
    $familyNames = @($families.Keys | Where-Object { $families[$_].Count -gt 0 })
    $currentFamily = if ($CurrentVersionKey -like 'W10_*') { 'Windows 10' } else { 'Windows 11' }
    if ($PresetTarget) {
        $currentFamily = if ($PresetTarget -like 'W10_*') { 'Windows 10' } else { 'Windows 11' }
    }

    $selectedFamily = $currentFamily
    if ($familyNames.Count -gt 1) {
        Write-Separator
        Write-Header 'SELECT TARGET FAMILY'
        for ($i = 0; $i -lt $familyNames.Count; $i++) {
            Write-Color "    [$($i + 1)]  $($familyNames[$i])" White
        }
        Write-Color "    [0]  Cancel / Exit" DarkGray
        Write-Host ''

        while ($true) {
            $defaultIndex = [Math]::Max(1, ([array]::IndexOf($familyNames, $currentFamily) + 1))
            Write-Color "    Select family [1-$($familyNames.Count)] (default: $defaultIndex): " Yellow -NoNewLine
            $familyInput = Read-Host
            if ([string]::IsNullOrWhiteSpace($familyInput)) {
                $selectedFamily = $familyNames[$defaultIndex - 1]
                break
            }
            elseif ($familyInput -eq '0') {
                return $null
            }
            elseif ($familyInput -match '^\d+$' -and [int]$familyInput -ge 1 -and [int]$familyInput -le $familyNames.Count) {
                $selectedFamily = $familyNames[[int]$familyInput - 1]
                break
            }
            else {
                Write-Color '    Invalid selection. Try again.' Red
            }
        }
    }

    $familyTargets = @($families[$selectedFamily])
    if ($familyTargets.Count -eq 1) {
        return $familyTargets[0]
    }

    Write-Separator
    Write-Header "SELECT $selectedFamily TARGET VERSION"
    for ($i = 0; $i -lt $familyTargets.Count; $i++) {
        $displayName = Get-VersionDisplayName $familyTargets[$i]
        $marker = if ($i -eq ($familyTargets.Count - 1)) { ' (latest)' } else { '' }
        Write-Color "    [$($i + 1)]  $displayName$marker" White
    }
    Write-Color "    [0]  Cancel / Exit" DarkGray
    Write-Host ''

    while ($true) {
        $defaultIndex = $familyTargets.Count
        Write-Color "    Select target [1-$($familyTargets.Count)] (default: $defaultIndex): " Yellow -NoNewLine
        $targetInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($targetInput)) {
            return $familyTargets[-1]
        }
        elseif ($targetInput -eq '0') {
            return $null
        }
        elseif ($targetInput -match '^\d+$' -and [int]$targetInput -ge 1 -and [int]$targetInput -le $familyTargets.Count) {
            return $familyTargets[[int]$targetInput - 1]
        }
        else {
            Write-Color '    Invalid selection. Try again.' Red
        }
    }
}

# ---------------------------------------------
# Region: System Detection
# ---------------------------------------------

function Get-SystemInfo {
    $ntVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$ntVer.CurrentBuildNumber
    $ubr = [int]$ntVer.UBR
    $display = $ntVer.DisplayVersion   # "22H2", "25H2" etc. -- exists on Win10 2004+ and all Win11
    $relId = $ntVer.ReleaseId        # "1809", "1903", "2004" etc. -- old style, stops at "2009"
    $edition = $ntVer.EditionID
    $product = $ntVer.ProductName

    # OS generation from build number (always reliable)
    $osName = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $osPrefix = if ($build -ge 22000) { '' } else { 'W10_' }

    # Feature version from the ACTUAL registry value
    $featureVersion = $null
    if ($display) {
        $featureVersion = $display
    }
    elseif ($relId -and $relId -ne '2009') {
        $featureVersion = $relId
    }

    # Build version key
    if ($featureVersion) {
        $versionKey = "${osPrefix}${featureVersion}"
    }
    else {
        # Fallback for ancient builds without DisplayVersion
        if ($build -ge 22000) { $versionKey = '21H2' }
        elseif ($build -ge 19041) { $versionKey = 'W10_2004' }
        elseif ($build -ge 18363) { $versionKey = 'W10_1909' }
        elseif ($build -ge 18362) { $versionKey = 'W10_1903' }
        elseif ($build -ge 17763) { $versionKey = 'W10_1809' }
        elseif ($build -ge 17134) { $versionKey = 'W10_1803' }
        elseif ($build -ge 16299) { $versionKey = 'W10_1709' }
        elseif ($build -ge 15063) { $versionKey = 'W10_1703' }
        elseif ($build -ge 14393) { $versionKey = 'W10_1607' }
        else { $versionKey = 'Unknown' }
    }

    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($disk.Size / 1GB, 1)

    $tpmStatus = 'Not detected'
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) { $tpmStatus = "v$($tpm.SpecVersion.Split(',')[0].Trim())" }
    }
    catch {}

    $sbStatus = 'Unknown'
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        $sbStatus = if ($sb) { 'Enabled' } else { 'Disabled' }
    }
    catch { $sbStatus = 'N/A (BIOS)' }

    return @{
        ComputerName = $cs.Name
        Product      = $product
        Edition      = $edition
        Display      = $display
        VersionKey   = $versionKey
        Build        = $build
        UBR          = $ubr
        FullBuild    = "$build.$ubr"
        OS           = $osName
        CPU          = $cpu.Trim()
        RAM          = $ram
        DiskFree     = $freeGB
        DiskTotal    = $totalGB
        TPM          = $tpmStatus
        SecureBoot   = $sbStatus
    }
}

# ---------------------------------------------
# Region: Version Chain
# ---------------------------------------------

# Fallback version map (used if API query fails)
$FallbackVersions = [ordered]@{
    'W10_20H2' = @{ Build = 19042; OS = 'Windows 10'; Name = 'Win10 20H2' }
    'W10_21H2' = @{ Build = 19044; OS = 'Windows 10'; Name = 'Win10 21H2' }
    'W10_22H2' = @{ Build = 19045; OS = 'Windows 10'; Name = 'Win10 22H2' }
    '21H2'     = @{ Build = 22000; OS = 'Windows 11'; Name = 'Win11 21H2' }
    '22H2'     = @{ Build = 22621; OS = 'Windows 11'; Name = 'Win11 22H2' }
    '23H2'     = @{ Build = 22631; OS = 'Windows 11'; Name = 'Win11 23H2' }
    '24H2'     = @{ Build = 26100; OS = 'Windows 11'; Name = 'Win11 24H2' }
    '25H2'     = @{ Build = 26200; OS = 'Windows 11'; Name = 'Win11 25H2' }
}

# Will be populated dynamically after system scan
$VersionNames = @()
$VersionBuilds = [ordered]@{}
$RemoteVersions = @()

function Get-VersionDisplayName {
    param([string]$Key)
    if ($Key -like 'W10_*') { return "Win10 $($Key -replace 'W10_','')" }
    return "Win11 $Key"
}

function Get-UpgradePath {
    param([string]$CurrentKey)
    $currentBuild = $VersionBuilds[$CurrentKey]
    if (-not $currentBuild) { return @() }
    $targets = @()
    foreach ($k in $VersionNames) {
        if ($VersionBuilds[$k] -gt $currentBuild) { $targets += $k }
    }
    return $targets
}

# ---------------------------------------------
# Region: Banner
# ---------------------------------------------

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Color "  ============================================================" Cyan
    Write-Color "   wfu-tool" White
    Write-Color "   Win10/Win11 Upgrade Engine -- All Bypasses Enabled" DarkGray
    Write-Color "  ============================================================" Cyan
    Write-Host ""
}

# =====================================================
# Region: Option Resolution
# =====================================================

if ($Interactive) {
    $Mode = 'Interactive'
}
elseif ($Mode -eq 'Interactive') {
    if ($CreateUsb) {
        $Mode = 'CreateUsb'
    }
    elseif ($Headless) {
        $Mode = 'Headless'
    }
}
$Mode = Normalize-LauncherMode -Mode $Mode

$Script:ConfigData = $null
$Script:ConfigTargetProvided = $false
if ($ConfigPath -and (Get-Command Read-WfuIniFile -ErrorAction SilentlyContinue)) {
    try {
        $Script:ConfigData = Read-WfuIniFile -Path $ConfigPath
        if ($Script:ConfigData.Contains('general') -and $Script:ConfigData['general'].Contains('target_version')) {
            $Script:ConfigTargetProvided = $true
        }
    }
    catch {
        Write-Color "    WARNING: Could not read config file $ConfigPath : $($_.Exception.Message)" Yellow
    }
}

$launcherValues = Get-LauncherCurrentValues `
    -ScriptRoot $ScriptRoot `
    -Mode $Mode `
    -Interactive:$Interactive `
    -Headless:$Headless `
    -CreateUsb:$CreateUsb `
    -UsbDiskNumber $UsbDiskNumber `
    -UsbDiskId $UsbDiskId `
    -KeepIso:$KeepIso `
    -PreferredSource $PreferredSource `
    -ForceSource $ForceSource `
    -AllowDeadSources:$AllowDeadSources `
    -CheckpointPath $CheckpointPath `
    -SessionId $SessionId `
    -ResumeFromCheckpoint:$ResumeFromCheckpoint `
    -TargetVersion $TargetVersion `
    -LogPath $LogPath `
    -DownloadPath $DownloadPath `
    -NoReboot:$NoReboot `
    -ForceOnlineUpdate:$ForceOnlineUpdate `
    -MaxRetries $MaxRetries `
    -DirectIso:$DirectIso `
    -AllowFallback:$AllowFallback `
    -SkipBypasses:$SkipBypasses `
    -SkipBlockerRemoval:$SkipBlockerRemoval `
    -SkipTelemetry:$SkipTelemetry `
    -SkipRepair:$SkipRepair `
    -SkipCumulativeUpdates:$SkipCumulativeUpdates `
    -SkipNetworkCheck:$SkipNetworkCheck `
    -SkipDiskCheck:$SkipDiskCheck `
    -SkipDirectEsd:$SkipDirectEsd `
    -SkipEsd:$SkipEsd `
    -SkipFido:$SkipFido `
    -SkipMct:$SkipMct `
    -SkipAssistant:$SkipAssistant `
    -SkipWindowsUpdate:$SkipWindowsUpdate

if (Get-Command ConvertTo-WfuCliOptions -ErrorAction SilentlyContinue -and Get-Command New-WfuResolvedOptions -ErrorAction SilentlyContinue) {
    $cliOptions = ConvertTo-WfuCliOptions -BoundParameters $PSBoundParameters -CurrentValues $launcherValues
    $Script:ResolvedOptions = New-WfuResolvedOptions -ConfigPath $ConfigPath -CliOptions $cliOptions
}
else {
    $fallbackMode = Normalize-LauncherMode -Mode $Mode
    if ($fallbackMode -eq 'Interactive') {
        if ($CreateUsb) {
            $fallbackMode = 'UsbFromIso'
        }
        elseif ($Headless) {
            $fallbackMode = 'AutomatedUpgrade'
        }
    }
    $Script:ResolvedOptions = [ordered]@{
        Mode                  = $fallbackMode
        TargetVersion         = if ($TargetVersion) { $TargetVersion } else { '25H2' }
        DirectIso             = [bool]$DirectIso
        NoReboot              = [bool]$NoReboot
        AllowFallback         = [bool]$AllowFallback
        SkipBypasses          = [bool]$SkipBypasses
        SkipBlockerRemoval    = [bool]$SkipBlockerRemoval
        SkipTelemetry         = [bool]$SkipTelemetry
        SkipRepair            = [bool]$SkipRepair
        SkipCumulativeUpdates = [bool]$SkipCumulativeUpdates
        SkipNetworkCheck      = [bool]$SkipNetworkCheck
        SkipDiskCheck         = [bool]$SkipDiskCheck
        SkipDirectEsd         = [bool]$SkipDirectEsd
        SkipEsd               = [bool]$SkipEsd
        SkipFido              = [bool]$SkipFido
        SkipMct               = [bool]$SkipMct
        SkipAssistant         = [bool]$SkipAssistant
        SkipWindowsUpdate     = [bool]$SkipWindowsUpdate
        CreateUsb             = [bool]$CreateUsb
        UsbDiskNumber         = $UsbDiskNumber
        UsbDiskId             = $UsbDiskId
        KeepIso               = [bool]$KeepIso
        PreferredSource       = $PreferredSource
        ForceSource           = $ForceSource
        AllowDeadSources      = [bool]$AllowDeadSources
        CheckpointPath        = $CheckpointPath
        SessionId             = $SessionId
        ResumeFromCheckpoint  = [bool]$ResumeFromCheckpoint
        SourceHealth          = @{}
    }
}

$defaultOptions = Get-WfuDefaultOptions
$resolvedMode = Normalize-LauncherMode -Mode $Script:ResolvedOptions.Mode
$Script:ResolvedOptions.Mode = $resolvedMode
$interactiveMode = $resolvedMode -eq 'Interactive'
$isoDownloadMode = $resolvedMode -eq 'IsoDownload'
$usbMode = $resolvedMode -eq 'UsbFromIso'
$automatedUpgradeMode = $resolvedMode -eq 'AutomatedUpgrade'
$hasExplicitTarget = $PSBoundParameters.ContainsKey('TargetVersion') -or $Script:ConfigTargetProvided

# =====================================================
# Region: Main Interactive Flow
# =====================================================

Show-Banner

Write-Color "  [ADMIN] Running with elevated privileges" Green
Write-Host ""

# -- System scan --
Write-Separator
Show-Spinner -Message 'Scanning system...' -Seconds 1

$info = Get-SystemInfo

Write-Header 'SYSTEM INFORMATION'

# Detect locale for display -- active OS display language
$sysLocale = 'Unknown'
# Method 1: Get-WinUserLanguageList (active display language)
try {
    $ull = Get-WinUserLanguageList -ErrorAction SilentlyContinue
    if ($ull -and $ull.Count -gt 0) { $sysLocale = $ull[0].LanguageTag }
}
catch { }
# Method 2: Nls\Language\Default LCID
if ($sysLocale -eq 'Unknown') {
    try {
        $defLcid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -ErrorAction SilentlyContinue).Default
        if ($defLcid) { $sysLocale = ([System.Globalization.CultureInfo]::GetCultureInfo([int]"0x$defLcid")).Name }
    }
    catch { }
}
# Method 3: Get-WinSystemLocale
if ($sysLocale -eq 'Unknown') {
    try { $sysLocale = (Get-WinSystemLocale -ErrorAction SilentlyContinue).Name } catch { }
}
$userLocale = try { (Get-Culture).Name } catch { 'Unknown' }

Write-InfoLine 'Computer'      $info.ComputerName
Write-InfoLine 'OS'            "$($info.OS)  ($($info.Product))"
Write-InfoLine 'Edition'       $info.Edition
Write-InfoLine 'Feature Ver'   "$(Get-VersionDisplayName $info.VersionKey)" Cyan
Write-InfoLine 'Build'         "$($info.FullBuild)  (Build $($info.Build), UBR $($info.UBR))" Cyan
Write-InfoLine 'System Locale' "$sysLocale  (user: $userLocale)"
Write-InfoLine 'CPU'           $info.CPU
Write-InfoLine 'RAM'           "$($info.RAM) GB"
Write-InfoLine 'System Drive'  "$($env:SystemDrive) -- $($info.DiskFree) GB free / $($info.DiskTotal) GB"

Write-Host ""
Write-Separator
Write-Header 'HARDWARE STATUS (ALL BYPASSED)'

$tpmColor = if ($info.TPM -match '^v2') { 'Green' } else { 'Yellow' }
$sbColor = if ($info.SecureBoot -eq 'Enabled') { 'Green' } else { 'Yellow' }

$tpmDisplay = $info.TPM
if ($info.TPM -notmatch '^v2') { $tpmDisplay += '  >> BYPASSED' }
Write-InfoLine 'TPM' $tpmDisplay $tpmColor

$sbDisplay = $info.SecureBoot
if ($info.SecureBoot -ne 'Enabled') { $sbDisplay += '  >> BYPASSED' }
Write-InfoLine 'Secure Boot' $sbDisplay $sbColor

Write-Color "    All hardware checks are bypassed -- upgrade will proceed regardless." DarkGray
Write-Host ""

# -- Query remote versions --
Write-Separator
Write-Header 'AVAILABLE VERSIONS (LIVE)'

Write-Color "    Querying direct Windows Update + Microsoft APIs..." DarkGray

$versionTargets = @('25H2', '24H2', '23H2', '22H2', 'W10_22H2')

$RemoteVersions = @()
$wuWorked = $false

# Source 1: direct Windows Update metadata
foreach ($targetVersion in $versionTargets) {
    try {
        $release = Get-WindowsFeatureReleaseInfo -TargetVersion $targetVersion -Arch 'amd64'
        if ($release) {
            $RemoteVersions += $release
            $wuWorked = $true
        }
        Start-Sleep -Milliseconds 300
    }
    catch { }
}

# Source 2: Fido API (fallback)
if (-not $wuWorked) {
    $profileId = '606624d44113'
    $fidoProducts = @(
        @{ EditionId = 3262; Version = '25H2'; Build = 26200; OS = 'Windows 11' },
        @{ EditionId = 3113; Version = '24H2'; Build = 26100; OS = 'Windows 11' },
        @{ EditionId = 2935; Version = '23H2'; Build = 22631; OS = 'Windows 11' },
        @{ EditionId = 2618; Version = 'W10_22H2'; Build = 19045; OS = 'Windows 10' }
    )
    foreach ($product in $fidoProducts) {
        try {
            $sid = [guid]::NewGuid().ToString()
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sid" -ErrorAction SilentlyContinue | Out-Null
            $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=$profileId&productEditionId=$($product.EditionId)&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$sid"
            $skuResp = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 $skuUrl -ErrorAction Stop).Content | ConvertFrom-Json
            if ($skuResp.Skus -and $skuResp.Skus.Count -gt 0) {
                $engSku = $skuResp.Skus | Where-Object { $_.Language -eq 'English International' } | Select-Object -First 1
                $RemoteVersions += @{
                    Version          = $product.Version
                    Build            = $product.Build
                    OS               = $product.OS
                    LangCount        = $skuResp.Skus.Count
                    FriendlyFileName = if ($engSku.FriendlyFileNames) { $engSku.FriendlyFileNames[0] } else { '' }
                    Source           = 'Fido'
                    Available        = $true
                }
            }
        }
        catch { }
    }
}

# Build version map -- always start with full fallback, then enrich with remote data
# This ensures the current version is ALWAYS in the map regardless of API results
$VersionBuilds = [ordered]@{}
foreach ($k in $FallbackVersions.Keys) {
    $VersionBuilds[$k] = $FallbackVersions[$k].Build
}
# Ensure current version is in the map even if it's not in fallback (e.g. very old Win10)
if (-not $VersionBuilds.Contains($info.VersionKey)) {
    $VersionBuilds[$info.VersionKey] = $info.Build
}
$VersionNames = @($VersionBuilds.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Key })

if ($RemoteVersions.Count -gt 0) {
    foreach ($rv in ($RemoteVersions | Sort-Object { $_.Build } -Descending)) {
        $displayName = Get-VersionDisplayName $rv.Version
        $status = if ($rv.Build -le $info.Build) { 'CURRENT/OLDER' } else { 'AVAILABLE' }
        $color = if ($status -eq 'AVAILABLE') { 'Green' } else { 'DarkGray' }
        $buildStr = if ($rv.LatestBuild) { $rv.LatestBuild } else { "$($rv.Build)" }
        $extra = @()
        if ($rv.LangCount) { $extra += "$($rv.LangCount) langs" }
        if ($rv.FriendlyFileName) { $extra += $rv.FriendlyFileName }
        if ($rv.Name -and $rv.Source -eq 'DirectMetadata') { $extra += $rv.Name }
        $extraStr = if ($extra) { "  ($($extra -join ', '))" } else { '' }
        Write-Color "    $($displayName.PadRight(14))" $color -NoNewLine
        Write-Color "Build $buildStr".PadRight(22) DarkGray -NoNewLine
        Write-Color "$status$extraStr" $color
    }
    Write-Color "    Source: $($RemoteVersions[0].Source)" DarkGray
}
else {
    # API failed -- version map already built from fallback above
    Write-Color "    Could not reach Microsoft servers. Using offline version list." Yellow
    foreach ($k in $FallbackVersions.Keys) {
        $displayName = Get-VersionDisplayName $k
        Write-Color "    $($displayName.PadRight(16))Build $($FallbackVersions[$k].Build)" DarkGray
    }
}

Write-Host ""

# -- Upgrade path --
Write-Separator
Write-Header 'UPGRADE PATHS'

$available = Get-UpgradePath -CurrentKey $info.VersionKey

if ($available.Count -eq 0) {
    Write-Color "    You are already on the latest available version ($(Get-VersionDisplayName $info.VersionKey))!" Green
    Write-Color "    No upgrades available." DarkGray
    Write-Host ""
    return
}

$currentDisplay = Get-VersionDisplayName $info.VersionKey
$latestDisplay = Get-VersionDisplayName $available[-1]
$isCrossGen = ($info.VersionKey -like 'W10_*')

# Show stepped (sequential) path
Write-Color "    Stepped path:" DarkGray
Write-Host "      " -NoNewline
Write-Color "[$currentDisplay]" Green -NoNewLine
foreach ($v in $available) {
    Write-Color " -> " DarkGray -NoNewLine
    Write-Color "[$(Get-VersionDisplayName $v)]" Cyan -NoNewLine
}
Write-Host ""
Write-Color "      $($available.Count) step(s), $($available.Count) reboot(s), uses WU/ESD per step" DarkGray
Write-Host ""

# Show direct paths
Write-Color "    Direct paths (ISO, 1 reboot each):" DarkGray
foreach ($v in $available) {
    $vDisp = Get-VersionDisplayName $v
    $crossTag = ''
    if ($isCrossGen -and -not ($v -like 'W10_*')) { $crossTag = ' [CROSS-GEN]' }
    Write-Color "      [$currentDisplay] --> [$vDisp]$crossTag" White
}
Write-Host ""

# -- Operation mode selection --
Write-Separator
$selectedMode = Select-LauncherMode -DefaultMode $resolvedMode
if (-not $selectedMode) {
    Write-Color "    Cancelled." DarkGray
    return
}
$resolvedMode = Normalize-LauncherMode -Mode $selectedMode
$Script:ResolvedOptions.Mode = $resolvedMode
$interactiveMode = $resolvedMode -eq 'Interactive'
$isoDownloadMode = $resolvedMode -eq 'IsoDownload'
$usbMode = $resolvedMode -eq 'UsbFromIso'
$automatedUpgradeMode = $resolvedMode -eq 'AutomatedUpgrade'
if ($usbMode) {
    $Script:ResolvedOptions.CreateUsb = $true
}

# -- Target selection --
Write-Separator
Write-Header 'SELECT TARGET VERSION'

$selectedTarget = Select-WfuTargetVersion -CurrentVersionKey $info.VersionKey -AvailableTargets $available -PresetTarget $(if ($hasExplicitTarget) { $Script:ResolvedOptions.TargetVersion } else { $null }) -AllowPrompt:$true
if (-not $selectedTarget) {
    Write-Color "    Cancelled." DarkGray
    return
}

if ($usbMode) {
    $usbSelection = Select-LauncherUsbDisk -DefaultDiskNumber $Script:ResolvedOptions.UsbDiskNumber -DefaultDiskId $Script:ResolvedOptions.UsbDiskId
    if (-not $usbSelection) {
        Write-Color "    Cancelled." DarkGray
        return
    }
    $Script:ResolvedOptions.UsbDiskNumber = $usbSelection.UsbDiskNumber
    $Script:ResolvedOptions.UsbDiskId = $usbSelection.UsbDiskId
}

# Build the steps to target
$stepsToTarget = @()
foreach ($v in $available) {
    $stepsToTarget += $v
    if ($v -eq $selectedTarget) { break }
}

# -- Mode-specific execution options --
Write-Host ""
Write-Separator

$skipCount = $stepsToTarget.Count
$isCrossGen = ($info.VersionKey -like 'W10_*' -and -not ($selectedTarget -like 'W10_*'))
$currentDisp = Get-VersionDisplayName $info.VersionKey
$targetDisp = Get-VersionDisplayName $selectedTarget
$stepsDisp = ($stepsToTarget | ForEach-Object { Get-VersionDisplayName $_ }) -join ' -> '
$directIso = $false
$noReboot = -not $Script:ResolvedOptions.NoReboot
$doBypass = -not $Script:ResolvedOptions.SkipBypasses
$doBlockRemoval = -not $Script:ResolvedOptions.SkipBlockerRemoval
$doTelemetry = -not $Script:ResolvedOptions.SkipTelemetry
$doRepair = -not $Script:ResolvedOptions.SkipRepair
$doCumulative = -not $Script:ResolvedOptions.SkipCumulativeUpdates
$doNetwork = -not $Script:ResolvedOptions.SkipNetworkCheck
$doDisk = -not $Script:ResolvedOptions.SkipDiskCheck
$discardIso = $false

$sourceHealthMap = if ($Script:ResolvedOptions.SourceHealth) { $Script:ResolvedOptions.SourceHealth } else { @{} }
function Test-LauncherSourceDead {
    param([string]$SourceId)
    if (-not $SourceId) { return $false }
    if (-not (Get-Command Get-WfuSourceHealth -ErrorAction SilentlyContinue)) { return $false }
    return (Get-WfuSourceHealth -SourceId $SourceId -HealthMap $sourceHealthMap) -eq 'dead'
}

$directSourceLabel = Get-SourceHealthLabel -SourceId 'WU_DIRECT' -HealthMap $sourceHealthMap
$esdSourceLabel = Get-SourceHealthLabel -SourceId 'ESD_CATALOG' -HealthMap $sourceHealthMap
$fidoSourceLabel = Get-SourceHealthLabel -SourceId 'FIDO' -HealthMap $sourceHealthMap
$mctSourceLabel = Get-SourceHealthLabel -SourceId 'MCT' -HealthMap $sourceHealthMap
$assistantSourceLabel = Get-SourceHealthLabel -SourceId 'ASSISTANT' -HealthMap $sourceHealthMap
$wuSourceLabel = Get-SourceHealthLabel -SourceId 'WINDOWS_UPDATE' -HealthMap $sourceHealthMap

$upgradeMethodItems = @(
    @{ Name = "Direct WU ESD$directSourceLabel"; Description = '(Microsoft CDN, all versions, from the direct metadata client)'; Enabled = -not (Test-LauncherSourceDead 'WU_DIRECT') -and -not $Script:ResolvedOptions.SkipDirectEsd },
    @{ Name = "ESD catalog download$esdSourceLabel"; Description = '(permanent CDN, SHA1, 22H2/23H2 only)'; Enabled = -not (Test-LauncherSourceDead 'ESD_CATALOG') -and -not $Script:ResolvedOptions.SkipEsd },
    @{ Name = "Fido direct ISO download$fidoSourceLabel"; Description = '(ov-df API, 24h links, may be Sentinel-blocked)'; Enabled = -not (Test-LauncherSourceDead 'FIDO') -and -not $Script:ResolvedOptions.SkipFido },
    @{ Name = "Media Creation Tool ISO$mctSourceLabel"; Description = '(UI automation, needs working internet to MCT)'; Enabled = -not (Test-LauncherSourceDead 'MCT') -and -not $Script:ResolvedOptions.SkipMct },
    @{ Name = "Installation Assistant$assistantSourceLabel"; Description = '(with IFEO hook + health check killer)'; Enabled = -not (Test-LauncherSourceDead 'ASSISTANT') -and -not $Script:ResolvedOptions.SkipAssistant },
    @{ Name = "Windows Update API$wuSourceLabel"; Description = '(WU COM, slowest, may be policy-blocked)'; Enabled = -not (Test-LauncherSourceDead 'WINDOWS_UPDATE') -and -not $Script:ResolvedOptions.SkipWindowsUpdate },
    @{ Name = 'Sequential step fallback'; Description = '(fall back to step-by-step if direct fails)'; Enabled = [bool]$Script:ResolvedOptions.AllowFallback }
)

$downloadSourceItems = @($upgradeMethodItems[0..3])

if ($interactiveMode -or $automatedUpgradeMode) {
    # -- Pre-flight step selection --
    Write-Host ""
    Write-Separator

    $stepDefaults = @{
        Bypasses     = -not $Script:ResolvedOptions.SkipBypasses
        BlockRemoval = -not $Script:ResolvedOptions.SkipBlockerRemoval
        Telemetry    = -not $Script:ResolvedOptions.SkipTelemetry
        Repair       = -not $Script:ResolvedOptions.SkipRepair
        Cumulative   = -not $Script:ResolvedOptions.SkipCumulativeUpdates
        Network      = -not $Script:ResolvedOptions.SkipNetworkCheck
        Disk         = -not $Script:ResolvedOptions.SkipDiskCheck
        AutoReboot   = -not $Script:ResolvedOptions.NoReboot
        DiscardIso   = $false
    }

    $stepItems = @(
        @{ Name = 'Hardware bypasses'; Description = '(compatibility registry patches)'; Enabled = $stepDefaults.Bypasses },
        @{ Name = 'Remove upgrade blocks'; Description = '(policies, deferrals, WSUS)'; Enabled = $stepDefaults.BlockRemoval },
        @{ Name = 'Telemetry suppression'; Description = '(disable tracking services)'; Enabled = $stepDefaults.Telemetry },
        @{ Name = 'Component store repair'; Description = '(DISM /RestoreHealth + SFC)'; Enabled = -not $Script:ResolvedOptions.SkipRepair },
        @{ Name = 'Cumulative updates'; Description = '(install pending patches first)'; Enabled = $stepDefaults.Cumulative },
        @{ Name = 'Network check'; Description = '(test WU endpoint connectivity)'; Enabled = $stepDefaults.Network },
        @{ Name = 'Disk space check'; Description = '(auto-cleanup if low)'; Enabled = $stepDefaults.Disk },
        @{ Name = 'Auto-reboot'; Description = '(30s countdown between steps)'; Enabled = $stepDefaults.AutoReboot },
        @{ Name = 'Discard cached ISO/ESD'; Description = '(delete previous downloads)'; Enabled = $stepDefaults.DiscardIso }
    )

    $stepItems = Show-ToggleMenu -Items $stepItems -Title 'CONFIGURE PRE-FLIGHT STEPS'

    $doBypass = $stepItems[0].Enabled
    $doBlockRemoval = $stepItems[1].Enabled
    $doTelemetry = $stepItems[2].Enabled
    $doRepair = $stepItems[3].Enabled
    $doCumulative = $stepItems[4].Enabled
    $doNetwork = $stepItems[5].Enabled
    $doDisk = $stepItems[6].Enabled
    $noReboot = -not $stepItems[7].Enabled
    $discardIso = $stepItems[8].Enabled

    # Delete cached ISO/ESD if requested
    if ($discardIso) {
        $dlPath = 'C:\wfu-tool'

        try {
            Get-DiskImage -ImagePath "$dlPath\Windows11.iso" -ErrorAction SilentlyContinue |
                Where-Object { $_.Attached } |
                ForEach-Object {
                    Dismount-DiskImage -ImagePath $_.ImagePath -ErrorAction SilentlyContinue
                    Write-Color "    Dismounted: $($_.ImagePath)" DarkGray
                }
        }
        catch { }

        foreach ($cached in @("$dlPath\Windows11.iso", "$dlPath\install.esd", "$dlPath\SetupWork", "$dlPath\EsdExtracted", "$dlPath\MCT")) {
            if (Test-Path $cached) {
                Remove-Item $cached -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $cached) {
                    Write-Color "    Force-deleting locked: $cached" Yellow
                    & cmd.exe /c "rd /s /q `"$cached`"" 2>$null
                    & cmd.exe /c "del /f /q `"$cached`"" 2>$null
                }
                if (-not (Test-Path $cached)) {
                    Write-Color "    Discarded: $cached" DarkGray
                }
                else {
                    Write-Color "    COULD NOT DELETE: $cached (may be in use)" Red
                }
            }
        }
    }
}

if ($interactiveMode -or $automatedUpgradeMode) {
    Write-Host ''
    Write-Separator
    $methodItems = Show-ToggleMenu -Items $upgradeMethodItems -Title 'CONFIGURE DOWNLOAD / UPGRADE METHODS'
    $useDirectEsd = $methodItems[0].Enabled
    $useEsd = $methodItems[1].Enabled
    $useFido = $methodItems[2].Enabled
    $useMct = $methodItems[3].Enabled
    $useAssistant = $methodItems[4].Enabled
    $useWU = $methodItems[5].Enabled
    $allowFallback = $methodItems[6].Enabled
    if ($isCrossGen) {
        $directIso = $true
    }
    elseif ($Script:ResolvedOptions.DirectIso -or $usbMode -or $isoDownloadMode) {
        $directIso = [bool]$Script:ResolvedOptions.DirectIso -or $usbMode -or $isoDownloadMode
    }
    else {
        $upgradeMethod = $null
        while ($null -eq $upgradeMethod) {
            Write-Color "    Select method [1-2] (default: 1 = Direct ISO): " Yellow -NoNewLine
            $methodInput = Read-Host
            if ([string]::IsNullOrWhiteSpace($methodInput)) {
                $upgradeMethod = 1
            }
            elseif ($methodInput -eq '0') {
                Write-Color "    Cancelled." DarkGray
                return
            }
            elseif ($methodInput -match '^[12]$') {
                $upgradeMethod = [int]$methodInput
            }
            else {
                Write-Color "    Invalid selection." Red
            }
        }
        $directIso = ($upgradeMethod -eq 1)
    }
}
else {
    $methodItems = @()
    $methodItems = Show-ToggleMenu -Items $downloadSourceItems -Title 'CONFIGURE ISO SOURCES'
    $useDirectEsd = $methodItems[0].Enabled
    $useEsd = $methodItems[1].Enabled
    $useFido = $methodItems[2].Enabled
    $useMct = $methodItems[3].Enabled
    $useAssistant = $false
    $useWU = $false
    $allowFallback = $false
    $directIso = $true
}

if ($isoDownloadMode -or $usbMode) {
    $noReboot = $true
}

Write-Separator
Write-Header 'CONFIRM UPGRADE PLAN'

Write-Color "    Mode     : " DarkGray -NoNewLine
switch ($resolvedMode) {
    'IsoDownload' { Write-Color 'Just download ISO' Cyan }
    'UsbFromIso' { Write-Color 'Download/use ISO and make USB drive' Cyan }
    'AutomatedUpgrade' { Write-Color 'Automated in-place upgrade' Cyan }
    default { Write-Color 'Interactive' Cyan }
}

Write-Color "    Target   : " DarkGray -NoNewLine
Write-Color "$targetDisp" Yellow

if ($usbMode) {
    Write-Color "    USB disk : " DarkGray -NoNewLine
    if ($Script:ResolvedOptions.UsbDiskNumber) {
        Write-Color "Disk $($Script:ResolvedOptions.UsbDiskNumber)" White
    }
    elseif ($Script:ResolvedOptions.UsbDiskId) {
        Write-Color $Script:ResolvedOptions.UsbDiskId White
    }
    else {
        Write-Color '(manual selection)' White
    }
}

if ($interactiveMode -or $automatedUpgradeMode) {
    Write-Color "    Method   : " DarkGray -NoNewLine
    if ($directIso) {
        Write-Color "Direct ISO ($currentDisp -> $targetDisp, 1 reboot)" Green
    }
    else {
        Write-Color "Sequential ($currentDisp -> $stepsDisp, $skipCount reboot(s))" Yellow
    }
    Write-Color "    Steps    : " DarkGray -NoNewLine
    $enabledSteps = ($stepItems | Where-Object { $_.Enabled }).Name -join ', '
    if (-not $enabledSteps) { $enabledSteps = '(none)' }
    Write-Color "$enabledSteps" White
    Write-Color "    Reboot   : " DarkGray -NoNewLine
    if ($noReboot) {
        Write-Color "Manual (you will be prompted)" Yellow
    }
    else {
        Write-Color "Automatic (30s countdown)" Green
    }
    Write-Color "    Downloads: " DarkGray -NoNewLine
    $enabledMethods = ($methodItems | Where-Object { $_.Enabled }).Name -join ', '
    if (-not $enabledMethods) { $enabledMethods = '(none -- will fail!)' }
    Write-Color "$enabledMethods" White
    Write-Color "    Fallback : " DarkGray -NoNewLine
    if ($allowFallback) {
        Write-Color "Enabled (sequential step-by-step if direct fails)" Yellow
    }
    else {
        Write-Color "Disabled (stop if all enabled methods fail)" DarkGray
    }
}
else {
    Write-Color "    Action   : " DarkGray -NoNewLine
    if ($isoDownloadMode) {
        Write-Color 'Download or reuse ISO, then stop' White
    }
    elseif ($usbMode) {
        Write-Color 'Download or reuse ISO, then write USB media' White
    }
    Write-Color "    Sources  : " DarkGray -NoNewLine
    $enabledMethods = ($methodItems | Where-Object { $_.Enabled }).Name -join ', '
    if (-not $enabledMethods) { $enabledMethods = '(none)' }
    Write-Color "$enabledMethods" White
}

Write-Host ""
$configBuilderOptions = New-LauncherConfigOptions `
    -Mode $resolvedMode `
    -TargetVersion $selectedTarget `
    -LogPath $(if ($Script:ResolvedOptions.LogPath) { $Script:ResolvedOptions.LogPath } else { $LogPath }) `
    -DownloadPath $(if ($Script:ResolvedOptions.DownloadPath) { $Script:ResolvedOptions.DownloadPath } else { $DownloadPath }) `
    -NoReboot $noReboot `
    -DirectIso $directIso `
    -AllowFallback $allowFallback `
    -ForceOnlineUpdate ([bool]$Script:ResolvedOptions.ForceOnlineUpdate) `
    -MaxRetries $(if ($Script:ResolvedOptions.MaxRetries) { [int]$Script:ResolvedOptions.MaxRetries } else { $MaxRetries }) `
    -SkipBypasses (-not $doBypass) `
    -SkipBlockerRemoval (-not $doBlockRemoval) `
    -SkipTelemetry (-not $doTelemetry) `
    -SkipRepair (-not $doRepair) `
    -SkipCumulativeUpdates (-not $doCumulative) `
    -SkipNetworkCheck (-not $doNetwork) `
    -SkipDiskCheck (-not $doDisk) `
    -SkipDirectEsd (-not $useDirectEsd) `
    -SkipEsd (-not $useEsd) `
    -SkipFido (-not $useFido) `
    -SkipMct (-not $useMct) `
    -SkipAssistant (-not $useAssistant) `
    -SkipWindowsUpdate (-not $useWU) `
    -CreateUsb ([bool]$usbMode -or [bool]$Script:ResolvedOptions.CreateUsb) `
    -UsbDiskNumber $Script:ResolvedOptions.UsbDiskNumber `
    -UsbDiskId $Script:ResolvedOptions.UsbDiskId `
    -KeepIso ([bool]$Script:ResolvedOptions.KeepIso) `
    -PreferredSource $Script:ResolvedOptions.PreferredSource `
    -ForceSource $Script:ResolvedOptions.ForceSource `
    -AllowDeadSources ([bool]$Script:ResolvedOptions.AllowDeadSources) `
    -CheckpointPath $Script:ResolvedOptions.CheckpointPath `
    -SessionId $Script:ResolvedOptions.SessionId `
    -ResumeFromCheckpoint ([bool]$Script:ResolvedOptions.ResumeFromCheckpoint) `
    -SourceHealth $sourceHealthMap

$defaultConfigPath = Join-Path $ScriptRoot 'configs\wfu-tool-default.ini'
$modeConfigPath = Join-Path $ScriptRoot "configs\wfu-tool-$selectedTarget.ini"
$configSavePath = $modeConfigPath

Write-Color "    Actions: " DarkGray -NoNewLine
Write-Color "[Y]" Yellow -NoNewLine
Write-Color " launch  " DarkGray -NoNewLine
Write-Color "[S]" Yellow -NoNewLine
Write-Color " save config + launch  " DarkGray -NoNewLine
Write-Color "[C]" Yellow -NoNewLine
Write-Color " save config only  " DarkGray -NoNewLine
Write-Color "[D]" Yellow -NoNewLine
Write-Color " save default template  " DarkGray -NoNewLine
Write-Color "[N]" Yellow -NoNewLine
Write-Color " cancel" DarkGray
Write-Color "    > " Yellow -NoNewLine
$confirm = Read-Host

if ($confirm -match '^[nN]') {
    Write-Host ""
    Write-Color "    Upgrade cancelled." DarkGray
    return
}

if ($confirm -match '^[dD]') {
    $defaultSavePath = Read-ConfigSavePath -DefaultPath $defaultConfigPath
    try {
        $savedDefaultPath = Save-LauncherDefaultIniConfig -Path $defaultSavePath
        Write-Color "    Default template saved: $savedDefaultPath" Green
    }
    catch {
        Write-Color "    Failed to save default template: $($_.Exception.Message)" Red
    }
    return
}

if ($confirm -match '^[sScC]') {
    $configSavePath = Read-ConfigSavePath -DefaultPath $modeConfigPath
    try {
        $savedConfigPath = Save-WfuIniConfig -Path $configSavePath -Options $configBuilderOptions
        Write-Color "    Config saved: $savedConfigPath" Green
        $ConfigPath = $savedConfigPath
    }
    catch {
        Write-Color "    Failed to save config: $($_.Exception.Message)" Red
        return
    }

    if ($confirm -match '^[cC]') {
        Write-Host ""
        Write-Color "    Config builder complete. Re-run with -ConfigPath `"$savedConfigPath`" or use the saved config." Green
        return
    }
}

# -- Launch --
Write-Host ""
Write-Separator
Write-Header 'LAUNCHING UPGRADE ENGINE'

Show-Spinner -Message 'Preparing upgrade environment...' -Seconds 1

$upgradeScript = Join-Path $ScriptRoot 'wfu-tool.ps1'

if (-not (Test-Path $upgradeScript)) {
    Write-Color "  ERROR: Cannot find wfu-tool.ps1 at:" Red
    Write-Color "  $upgradeScript" Red
    return
}

# Build params for the upgrade engine
$upgradeParams = [ordered]@{
    TargetVersion = $selectedTarget
    Mode          = Get-LauncherRuntimeMode -Mode $resolvedMode
    ConfigPath    = $ConfigPath
    LogPath       = if ($Script:ResolvedOptions.LogPath) { $Script:ResolvedOptions.LogPath } else { $LogPath }
    DownloadPath  = if ($Script:ResolvedOptions.DownloadPath) { $Script:ResolvedOptions.DownloadPath } else { $DownloadPath }
    MaxRetries    = if ($Script:ResolvedOptions.MaxRetries) { [int]$Script:ResolvedOptions.MaxRetries } else { $MaxRetries }
}
if ($noReboot) { $upgradeParams['NoReboot'] = $true }
if ($directIso) { $upgradeParams['DirectIso'] = $true }
if ($allowFallback) { $upgradeParams['AllowFallback'] = $true }
if ($Script:ResolvedOptions.ForceOnlineUpdate) { $upgradeParams['ForceOnlineUpdate'] = $true }
if ($usbMode -or $Script:ResolvedOptions.CreateUsb) { $upgradeParams['CreateUsb'] = $true }
if ($Script:ResolvedOptions.UsbDiskNumber) { $upgradeParams['UsbDiskNumber'] = $Script:ResolvedOptions.UsbDiskNumber }
if ($Script:ResolvedOptions.UsbDiskId) { $upgradeParams['UsbDiskId'] = $Script:ResolvedOptions.UsbDiskId }
if ($Script:ResolvedOptions.KeepIso) { $upgradeParams['KeepIso'] = $true }
if ($Script:ResolvedOptions.PreferredSource) { $upgradeParams['PreferredSource'] = $Script:ResolvedOptions.PreferredSource }
if ($Script:ResolvedOptions.ForceSource) { $upgradeParams['ForceSource'] = $Script:ResolvedOptions.ForceSource }
if ($Script:ResolvedOptions.AllowDeadSources) { $upgradeParams['AllowDeadSources'] = $true }
if ($Script:ResolvedOptions.CheckpointPath) { $upgradeParams['CheckpointPath'] = $Script:ResolvedOptions.CheckpointPath }
if ($Script:ResolvedOptions.SessionId) { $upgradeParams['SessionId'] = $Script:ResolvedOptions.SessionId }
if ($Script:ResolvedOptions.ResumeFromCheckpoint) { $upgradeParams['ResumeFromCheckpoint'] = $true }
if (-not $doBypass) { $upgradeParams['SkipBypasses'] = $true }
if (-not $doBlockRemoval) { $upgradeParams['SkipBlockerRemoval'] = $true }
if (-not $doTelemetry) { $upgradeParams['SkipTelemetry'] = $true }
if (-not $doRepair) { $upgradeParams['SkipRepair'] = $true }
if (-not $doCumulative) { $upgradeParams['SkipCumulativeUpdates'] = $true }
if (-not $doNetwork) { $upgradeParams['SkipNetworkCheck'] = $true }
if (-not $doDisk) { $upgradeParams['SkipDiskCheck'] = $true }
if (-not $useDirectEsd) { $upgradeParams['SkipDirectEsd'] = $true }
if (-not $useEsd) { $upgradeParams['SkipEsd'] = $true }
if (-not $useFido) { $upgradeParams['SkipFido'] = $true }
if (-not $useMct) { $upgradeParams['SkipMct'] = $true }
if (-not $useAssistant) { $upgradeParams['SkipAssistant'] = $true }
if (-not $useWU) { $upgradeParams['SkipWindowsUpdate'] = $true }

$paramDisplay = $upgradeParams.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }
Write-Color "    $($paramDisplay -join ' ')" Cyan
Write-Host ""
Write-Separator
Write-Host ""

# Run the upgrade engine in the same console
try {
    & $upgradeScript @upgradeParams
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Color "  ERROR: $($_.Exception.Message)" Red
    $exitCode = 1
}

# -- Done --
Write-Host ""
Write-Separator
Write-Host ""

if ($exitCode -eq 0 -or $null -eq $exitCode) {
    Write-Color "  Upgrade engine finished successfully." Green
}
else {
    Write-Color "  Upgrade engine exited with code $exitCode -- check the log." Yellow
}

$logFile = Join-Path $ScriptRoot 'wfu-tool.log'
if (Test-Path $logFile) {
    Write-Color "  Log: $logFile" DarkGray
}

Write-Host ""
