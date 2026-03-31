<#
.SYNOPSIS
    Interactive terminal UI for wfu-tool.
    Handles system info display, version detection, target selection,
    step configuration, and launches the main upgrade engine.
#>
param(
    [string]$ScriptRoot = $PSScriptRoot
)

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
} catch {
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
    $spinChars = @('|','/','-','\')
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
            } else {
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
        } elseif ($key -match '^[aA]$') {
            foreach ($item in $Items) { $item.Enabled = $true }
            Write-Host ""
        } elseif ($key -match '^[nN]$') {
            foreach ($item in $Items) { $item.Enabled = $false }
            Write-Host ""
        } else {
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

# ---------------------------------------------
# Region: System Detection
# ---------------------------------------------

function Get-SystemInfo {
    $ntVer   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build   = [int]$ntVer.CurrentBuildNumber
    $ubr     = [int]$ntVer.UBR
    $display = $ntVer.DisplayVersion   # "22H2", "25H2" etc. -- exists on Win10 2004+ and all Win11
    $relId   = $ntVer.ReleaseId        # "1809", "1903", "2004" etc. -- old style, stops at "2009"
    $edition = $ntVer.EditionID
    $product = $ntVer.ProductName

    # OS generation from build number (always reliable)
    $osName   = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $osPrefix = if ($build -ge 22000) { '' } else { 'W10_' }

    # Feature version from the ACTUAL registry value
    $featureVersion = $null
    if ($display) {
        $featureVersion = $display
    } elseif ($relId -and $relId -ne '2009') {
        $featureVersion = $relId
    }

    # Build version key
    if ($featureVersion) {
        $versionKey = "${osPrefix}${featureVersion}"
    } else {
        # Fallback for ancient builds without DisplayVersion
        if     ($build -ge 22000) { $versionKey = '21H2' }
        elseif ($build -ge 19041) { $versionKey = 'W10_2004' }
        elseif ($build -ge 18363) { $versionKey = 'W10_1909' }
        elseif ($build -ge 18362) { $versionKey = 'W10_1903' }
        elseif ($build -ge 17763) { $versionKey = 'W10_1809' }
        elseif ($build -ge 17134) { $versionKey = 'W10_1803' }
        elseif ($build -ge 16299) { $versionKey = 'W10_1709' }
        elseif ($build -ge 15063) { $versionKey = 'W10_1703' }
        elseif ($build -ge 14393) { $versionKey = 'W10_1607' }
        else                      { $versionKey = 'Unknown' }
    }

    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $ram  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($disk.Size / 1GB, 1)

    $tpmStatus = 'Not detected'
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) { $tpmStatus = "v$($tpm.SpecVersion.Split(',')[0].Trim())" }
    } catch {}

    $sbStatus = 'Unknown'
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        $sbStatus = if ($sb) { 'Enabled' } else { 'Disabled' }
    } catch { $sbStatus = 'N/A (BIOS)' }

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
} catch { }
# Method 2: Nls\Language\Default LCID
if ($sysLocale -eq 'Unknown') {
    try {
        $defLcid = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -ErrorAction SilentlyContinue).Default
        if ($defLcid) { $sysLocale = ([System.Globalization.CultureInfo]::GetCultureInfo([int]"0x$defLcid")).Name }
    } catch { }
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
$sbColor  = if ($info.SecureBoot -eq 'Enabled') { 'Green' } else { 'Yellow' }

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
    } catch { }
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
                    Version     = $product.Version
                    Build       = $product.Build
                    OS          = $product.OS
                    LangCount   = $skuResp.Skus.Count
                    FriendlyFileName = if ($engSku.FriendlyFileNames) { $engSku.FriendlyFileNames[0] } else { '' }
                    Source      = 'Fido'
                    Available   = $true
                }
            }
        } catch { }
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
} else {
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
$latestDisplay  = Get-VersionDisplayName $available[-1]
$isCrossGen     = ($info.VersionKey -like 'W10_*')

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

# -- Target selection --
Write-Separator
Write-Header 'SELECT TARGET VERSION'

for ($i = 0; $i -lt $available.Count; $i++) {
    $displayName = Get-VersionDisplayName $available[$i]
    $marker = if ($i -eq ($available.Count - 1)) { ' (latest)' } else { '' }
    $isCross = ($info.VersionKey -like 'W10_*' -and -not ($available[$i] -like 'W10_*'))
    $crossTag = if ($isCross) { '  [CROSS-GEN]' } else { '' }
    Write-Color "    [$($i + 1)]  $displayName$marker$crossTag" White
}
Write-Color "    [0]  Cancel / Exit" DarkGray
Write-Host ""

$selectedTarget = $null
while ($null -eq $selectedTarget) {
    Write-Color "    Select target [1-$($available.Count)] (default: $($available.Count) = latest): " Yellow -NoNewLine
    $selection = Read-Host
    if ([string]::IsNullOrWhiteSpace($selection)) {
        $selectedTarget = $available[-1]
    } elseif ($selection -eq '0') {
        Write-Color "    Cancelled." DarkGray
        return
    } elseif ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $available.Count) {
        $selectedTarget = $available[[int]$selection - 1]
    } else {
        Write-Color "    Invalid selection. Try again." Red
    }
}

# Build the steps to target
$stepsToTarget = @()
foreach ($v in $available) {
    $stepsToTarget += $v
    if ($v -eq $selectedTarget) { break }
}

# -- Upgrade method --
Write-Host ""
Write-Separator

$skipCount = $stepsToTarget.Count
$isCrossGen = ($info.VersionKey -like 'W10_*' -and -not ($selectedTarget -like 'W10_*'))
$currentDisp = Get-VersionDisplayName $info.VersionKey
$targetDisp  = Get-VersionDisplayName $selectedTarget
$stepsDisp   = ($stepsToTarget | ForEach-Object { Get-VersionDisplayName $_ }) -join ' -> '

if ($isCrossGen) {
    # Cross-generation: force Direct ISO, no choice
    Write-Header 'UPGRADE METHOD (AUTO-SELECTED)'
    Write-Color "    Cross-generation upgrade detected: $currentDisp -> $targetDisp" Yellow
    Write-Color "    Direct ISO is REQUIRED for Windows 10 -> Windows 11 upgrades." Yellow
    Write-Host ""
    Write-Color "    Method: Direct ISO (download + patched setup.exe, 1 reboot)" Green
    $directIso = $true
} else {
    Write-Header 'UPGRADE METHOD'

    Write-Color "    [1]  Direct ISO upgrade  " White -NoNewLine
    Write-Color "(RECOMMENDED)" Green
    Write-Color "         $currentDisp -> $targetDisp directly in one shot" DarkGray
    Write-Color "         Downloads official ISO, patches setup, 1 reboot" DarkGray
    Write-Host ""

    Write-Color "    [2]  Sequential (Windows Update, step by step)" DarkGray
    if ($skipCount -gt 1) {
        Write-Color "         $currentDisp -> $stepsDisp" DarkGray
        Write-Color "         $skipCount reboot(s), slower -- uses WU per step" DarkGray
    } else {
        Write-Color "         $currentDisp -> $targetDisp via WU" DarkGray
        Write-Color "         1 reboot, uses Windows Update / Installation Assistant" DarkGray
    }
    Write-Host ""
    Write-Color "    [0]  Cancel / Exit" DarkGray
    Write-Host ""

    $upgradeMethod = $null
    while ($null -eq $upgradeMethod) {
        Write-Color "    Select method [1-2] (default: 1 = Direct ISO): " Yellow -NoNewLine
        $methodInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($methodInput)) {
            $upgradeMethod = 1
        } elseif ($methodInput -eq '0') {
            Write-Color "    Cancelled." DarkGray
            return
        } elseif ($methodInput -match '^[12]$') {
            $upgradeMethod = [int]$methodInput
        } else {
            Write-Color "    Invalid selection." Red
        }
    }
    $directIso = ($upgradeMethod -eq 1)
}

# -- Pre-flight step selection --
Write-Host ""
Write-Separator

$stepItems = @(
    @{ Name = 'Hardware bypasses';     Description = '(compatibility registry patches)';    Enabled = $true },
    @{ Name = 'Remove upgrade blocks'; Description = '(policies, deferrals, WSUS)';     Enabled = $true },
    @{ Name = 'Telemetry suppression'; Description = '(disable tracking services)';     Enabled = $true },
    @{ Name = 'Component store repair';Description = '(DISM /RestoreHealth + SFC)';     Enabled = $false },
    @{ Name = 'Cumulative updates';    Description = '(install pending patches first)';  Enabled = $true },
    @{ Name = 'Network check';         Description = '(test WU endpoint connectivity)'; Enabled = $true },
    @{ Name = 'Disk space check';      Description = '(auto-cleanup if low)';           Enabled = $true },
    @{ Name = 'Auto-reboot';           Description = '(30s countdown between steps)';   Enabled = $true },
    @{ Name = 'Discard cached ISO/ESD';Description = '(delete previous downloads)';       Enabled = $true }
)
$stepItems = Show-ToggleMenu -Items $stepItems -Title 'CONFIGURE PRE-FLIGHT STEPS'

# Extract pre-flight toggles
$doBypass       = $stepItems[0].Enabled
$doBlockRemoval = $stepItems[1].Enabled
$doTelemetry    = $stepItems[2].Enabled
$doRepair       = $stepItems[3].Enabled
$doCumulative   = $stepItems[4].Enabled
$doNetwork      = $stepItems[5].Enabled
$doDisk         = $stepItems[6].Enabled
$noReboot       = -not $stepItems[7].Enabled
$discardIso     = $stepItems[8].Enabled

# Delete cached ISO/ESD if requested
if ($discardIso) {
    $dlPath = 'C:\wfu-tool'

    # Dismount any previously mounted ISOs first (they lock the file)
    try {
        Get-DiskImage -ImagePath "$dlPath\Windows11.iso" -ErrorAction SilentlyContinue |
            Where-Object { $_.Attached } |
            ForEach-Object {
                Dismount-DiskImage -ImagePath $_.ImagePath -ErrorAction SilentlyContinue
                Write-Color "    Dismounted: $($_.ImagePath)" DarkGray
            }
    } catch { }

    foreach ($cached in @("$dlPath\Windows11.iso", "$dlPath\install.esd", "$dlPath\SetupWork", "$dlPath\EsdExtracted", "$dlPath\MCT")) {
        if (Test-Path $cached) {
            Remove-Item $cached -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $cached) {
                # Still exists -- try harder (may be locked by a process)
                Write-Color "    Force-deleting locked: $cached" Yellow
                & cmd.exe /c "rd /s /q `"$cached`"" 2>$null
                & cmd.exe /c "del /f /q `"$cached`"" 2>$null
            }
            if (-not (Test-Path $cached)) {
                Write-Color "    Discarded: $cached" DarkGray
            } else {
                Write-Color "    COULD NOT DELETE: $cached (may be in use)" Red
            }
        }
    }
}

# -- Download / upgrade method toggles --
Write-Host ''
Write-Separator

$methodItems = @(
    @{ Name = 'Direct WU ESD';            Description = '(Microsoft CDN, all versions, from the direct metadata client)'; Enabled = $true },
    @{ Name = 'ESD catalog download';      Description = '(permanent CDN, SHA1, 22H2/23H2 only)';          Enabled = $true },
    @{ Name = 'Fido direct ISO download';  Description = '(ov-df API, 24h links, may be Sentinel-blocked)';Enabled = $true },
    @{ Name = 'Media Creation Tool ISO';   Description = '(UI automation, needs working internet to MCT)';  Enabled = $false },
    @{ Name = 'Installation Assistant';    Description = '(with IFEO hook + health check killer)';          Enabled = $false },
    @{ Name = 'Windows Update API';        Description = '(WU COM, slowest, may be policy-blocked)';        Enabled = $false },
    @{ Name = 'Sequential step fallback';  Description = '(fall back to step-by-step if direct fails)';     Enabled = $false }
)
$methodItems = Show-ToggleMenu -Items $methodItems -Title 'CONFIGURE DOWNLOAD / UPGRADE METHODS'

# Extract method toggles
$useDirectEsd          = $methodItems[0].Enabled
$useEsd          = $methodItems[1].Enabled
$useFido         = $methodItems[2].Enabled
$useMct          = $methodItems[3].Enabled
$useAssistant    = $methodItems[4].Enabled
$useWU           = $methodItems[5].Enabled
$allowFallback   = $methodItems[6].Enabled

# -- Confirm --
Write-Separator
Write-Header 'CONFIRM UPGRADE PLAN'

Write-Color "    Target   : " DarkGray -NoNewLine
Write-Color "$targetDisp" Yellow

Write-Color "    Method   : " DarkGray -NoNewLine
if ($directIso) {
    Write-Color "Direct ISO ($currentDisp -> $targetDisp, 1 reboot)" Green
} else {
    Write-Color "Sequential ($currentDisp -> $stepsDisp, $skipCount reboot(s))" Yellow
}

Write-Color "    Steps    : " DarkGray -NoNewLine
$enabledSteps = ($stepItems | Where-Object { $_.Enabled }).Name -join ', '
if (-not $enabledSteps) { $enabledSteps = '(none)' }
Write-Color "$enabledSteps" White

Write-Color "    Reboot   : " DarkGray -NoNewLine
if ($noReboot) {
    Write-Color "Manual (you will be prompted)" Yellow
} else {
    Write-Color "Automatic (30s countdown)" Green
}

Write-Color "    Downloads: " DarkGray -NoNewLine
$enabledMethods = ($methodItems | Where-Object { $_.Enabled }).Name -join ', '
if (-not $enabledMethods) { $enabledMethods = '(none -- will fail!)' }
Write-Color "$enabledMethods" White

Write-Color "    Fallback : " DarkGray -NoNewLine
if ($allowFallback) {
    Write-Color "Enabled (sequential step-by-step if direct fails)" Yellow
} else {
    Write-Color "Disabled (stop if all enabled methods fail)" DarkGray
}

Write-Host ""
Write-Color "    Proceed? [Y/n]: " Yellow -NoNewLine
$confirm = Read-Host

if ($confirm -match '^[nN]') {
    Write-Host ""
    Write-Color "    Upgrade cancelled." DarkGray
    return
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
$upgradeParams = @{
    TargetVersion = $selectedTarget
}
if ($noReboot)        { $upgradeParams['NoReboot'] = $true }
if ($directIso)       { $upgradeParams['DirectIso'] = $true }
if ($allowFallback)   { $upgradeParams['AllowFallback'] = $true }
if (-not $doBypass)       { $upgradeParams['SkipBypasses'] = $true }
if (-not $doBlockRemoval) { $upgradeParams['SkipBlockerRemoval'] = $true }
if (-not $doTelemetry)    { $upgradeParams['SkipTelemetry'] = $true }
if (-not $doRepair)       { $upgradeParams['SkipRepair'] = $true }
if (-not $doCumulative)   { $upgradeParams['SkipCumulativeUpdates'] = $true }
if (-not $doNetwork)      { $upgradeParams['SkipNetworkCheck'] = $true }
if (-not $doDisk)         { $upgradeParams['SkipDiskCheck'] = $true }
if (-not $useDirectEsd)         { $upgradeParams['SkipDirectEsd'] = $true }
if (-not $useEsd)         { $upgradeParams['SkipEsd'] = $true }
if (-not $useFido)        { $upgradeParams['SkipFido'] = $true }
if (-not $useMct)         { $upgradeParams['SkipMct'] = $true }
if (-not $useAssistant)   { $upgradeParams['SkipAssistant'] = $true }
if (-not $useWU)          { $upgradeParams['SkipWindowsUpdate'] = $true }

$paramDisplay = $upgradeParams.Keys | ForEach-Object { "-$_ $($upgradeParams[$_])" }
Write-Color "    $($paramDisplay -join ' ')" Cyan
Write-Host ""
Write-Separator
Write-Host ""

# Run the upgrade engine in the same console
try {
    & $upgradeScript @upgradeParams
    $exitCode = $LASTEXITCODE
} catch {
    Write-Color "  ERROR: $($_.Exception.Message)" Red
    $exitCode = 1
}

# -- Done --
Write-Host ""
Write-Separator
Write-Host ""

if ($exitCode -eq 0 -or $null -eq $exitCode) {
    Write-Color "  Upgrade engine finished successfully." Green
} else {
    Write-Color "  Upgrade engine exited with code $exitCode -- check the log." Yellow
}

$logFile = Join-Path $ScriptRoot 'wfu-tool.log'
if (Test-Path $logFile) {
    Write-Color "  Log: $logFile" DarkGray
}

Write-Host ""
