<#
.SYNOPSIS
    Interactive test that shows the full version detection result
    from both the upgrade engine and the interactive launcher.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  VERSION DETECTION TEST' -ForegroundColor Cyan
Write-Host '  ======================' -ForegroundColor Cyan
Write-Host ''

# Raw registry values
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Write-Host '  Raw Registry Values:' -ForegroundColor Yellow
Write-Host "    ProductName       : $($cv.ProductName)"
Write-Host "    DisplayVersion    : $($cv.DisplayVersion)"
Write-Host "    ReleaseId         : $($cv.ReleaseId)"
Write-Host "    CurrentBuild      : $($cv.CurrentBuild)"
Write-Host "    CurrentBuildNumber: $($cv.CurrentBuildNumber)"
Write-Host "    UBR               : $($cv.UBR)"
Write-Host "    EditionID         : $($cv.EditionID)"
Write-Host "    InstallationType  : $($cv.InstallationType)"
Write-Host "    BuildLabEx        : $($cv.BuildLabEx)"
Write-Host ''

# Source functions
$env:WFU_TOOL_TEST_MODE = '1'
try {
    . (Join-Path $projectRoot 'wfu-tool.ps1') -TargetVersion '25H2' -NoReboot `
        -LogPath (Join-Path $env:TEMP 'WFU_TOOL_VerTest.log') -DownloadPath (Join-Path $env:TEMP 'WFU_TOOL_VerTestDL') `
        -SkipBypasses -SkipBlockerRemoval -SkipTelemetry -SkipRepair `
        -SkipCumulativeUpdates -SkipNetworkCheck -SkipDiskCheck 2>$null
} catch { }

# Engine detection
Write-Host '  Engine Detection (Get-CurrentWindowsVersion):' -ForegroundColor Yellow
$ver = Get-CurrentWindowsVersion
$ver.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "    $($_.Name.PadRight(18)): $($_.Value)"
}

Write-Host ''
Write-Host '  Version Key Breakdown:' -ForegroundColor Yellow
$build = [int]$cv.CurrentBuildNumber
$dv = $cv.DisplayVersion
$osName = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
Write-Host "    OS determined from build ($build >= 22000?): $osName"
Write-Host "    Feature version from DisplayVersion: $dv"
Write-Host "    Combined key: $($ver.VersionKey)"

# Verify correctness
Write-Host ''
Write-Host '  Validation:' -ForegroundColor Yellow
$ok = $true
if ($dv -and $ver.VersionKey -notmatch $dv) {
    Write-Host "    MISMATCH: VersionKey '$($ver.VersionKey)' does not contain DisplayVersion '$dv'" -ForegroundColor Red
    $ok = $false
}
if ($ver.OS -ne $osName) {
    Write-Host "    MISMATCH: OS '$($ver.OS)' does not match expected '$osName'" -ForegroundColor Red
    $ok = $false
}
if ($ver.FullBuild -ne "$build.$($cv.UBR)") {
    Write-Host "    MISMATCH: FullBuild '$($ver.FullBuild)' != '$build.$($cv.UBR)'" -ForegroundColor Red
    $ok = $false
}
if ($ok) {
    Write-Host '    All checks PASSED' -ForegroundColor Green
}

Write-Host ''
