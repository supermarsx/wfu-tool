<#
.SYNOPSIS
    Test runner for wfu-tool scripts.
    Executes all test files in the tests directory and reports results.
    Run from project root: .\tests\Test-Runner.ps1
#>
param(
    [string]$Filter = '*',
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$testDir = $PSScriptRoot
$projectRoot = Split-Path $testDir -Parent

Write-Host ''
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host '  wfu-tool -- TEST SUITE' -ForegroundColor White
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host ''

# Dot-source the main script to load all functions (without running Start-UpgradeChain)
# We override params to prevent execution
$env:WFU_TOOL_TEST_MODE = '1'
if ($env:GITHUB_ACTIONS -eq 'true' -and -not $env:WFU_TOOL_CI_MODE) {
    $env:WFU_TOOL_CI_MODE = '1'
}
$Script:LogPath = Join-Path $env:TEMP 'WFU_TOOL_Test.log'
$Script:DownloadPath = Join-Path $env:TEMP 'WFU_TOOL_TestDL'
$Script:MaxRetries = 1

# Source the main script's functions
try {
    . (Join-Path $projectRoot 'wfu-tool.ps1') -TargetVersion '25H2' -NoReboot -LogPath $Script:LogPath -DownloadPath $Script:DownloadPath -SkipBypasses -SkipBlockerRemoval -SkipTelemetry -SkipRepair -SkipCumulativeUpdates -SkipNetworkCheck -SkipDiskCheck -MaxRetries 1
}
catch {
    # Expected -- the script runs Start-UpgradeChain which may fail in test context
}

# Test framework helpers
$Script:TotalTests = 0
$Script:PassedTests = 0
$Script:FailedTests = 0
$Script:SkippedTests = 0
$Script:FailedNames = @()

function Assert-True {
    param([bool]$Condition, [string]$TestName)
    $Script:TotalTests++
    if ($Condition) {
        $Script:PassedTests++
        Write-Host "    PASS: $TestName" -ForegroundColor Green
    }
    else {
        $Script:FailedTests++
        $Script:FailedNames += $TestName
        Write-Host "    FAIL: $TestName" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$TestName)
    $Script:TotalTests++
    if ($Expected -eq $Actual) {
        $Script:PassedTests++
        Write-Host "    PASS: $TestName" -ForegroundColor Green
    }
    else {
        $Script:FailedTests++
        $Script:FailedNames += $TestName
        Write-Host "    FAIL: $TestName (expected '$Expected', got '$Actual')" -ForegroundColor Red
    }
}

function Assert-NotNull {
    param($Value, [string]$TestName)
    $Script:TotalTests++
    if ($null -ne $Value -and $Value -ne '') {
        $Script:PassedTests++
        Write-Host "    PASS: $TestName" -ForegroundColor Green
    }
    else {
        $Script:FailedTests++
        $Script:FailedNames += $TestName
        Write-Host "    FAIL: $TestName (value is null/empty)" -ForegroundColor Red
    }
}

function Assert-Null {
    param($Value, [string]$TestName)
    $Script:TotalTests++
    if ($null -eq $Value) {
        $Script:PassedTests++
        Write-Host "    PASS: $TestName" -ForegroundColor Green
    }
    else {
        $Script:FailedTests++
        $Script:FailedNames += $TestName
        Write-Host "    FAIL: $TestName (expected null, got '$Value')" -ForegroundColor Red
    }
}

function Assert-Match {
    param([string]$Pattern, [string]$Value, [string]$TestName)
    $Script:TotalTests++
    if ($Value -match $Pattern) {
        $Script:PassedTests++
        Write-Host "    PASS: $TestName" -ForegroundColor Green
    }
    else {
        $Script:FailedTests++
        $Script:FailedNames += $TestName
        Write-Host "    FAIL: $TestName ('$Value' does not match '$Pattern')" -ForegroundColor Red
    }
}

function Skip-Test {
    param([string]$TestName, [string]$Reason)
    $Script:TotalTests++
    $Script:SkippedTests++
    Write-Host "    SKIP: $TestName ($Reason)" -ForegroundColor Yellow
}

# Export helpers for test files when hosted as a module
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function * -ErrorAction SilentlyContinue
}

# Find and run test files
if ($Filter -eq '*') {
    $testPattern = $null
}
else {
    $testPattern = "^Test-($Filter)$"
}

$testFiles = @(Get-ChildItem $testDir -Filter 'Test-*.ps1' | Where-Object {
        $_.Name -ne 'Test-Runner.ps1' -and (
            $null -eq $testPattern -or $_.BaseName -match $testPattern
        )
    } | Sort-Object Name)
Write-Host "  Found $($testFiles.Count) test file(s)" -ForegroundColor DarkGray
Write-Host ''

foreach ($testFile in $testFiles) {
    Write-Host "  $($testFile.BaseName)" -ForegroundColor Cyan
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
    try {
        . $testFile.FullName
    }
    catch {
        Write-Host "    ERROR: Test file threw exception: $_" -ForegroundColor Red
        $Script:FailedTests++
        $Script:FailedNames += "$($testFile.BaseName) (EXCEPTION)"
    }
    Write-Host ''
}

# Summary
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host '  RESULTS' -ForegroundColor White
Write-Host "    Total:   $Script:TotalTests" -ForegroundColor White
Write-Host "    Passed:  $Script:PassedTests" -ForegroundColor Green
Write-Host "    Failed:  $Script:FailedTests" -ForegroundColor $(if ($Script:FailedTests -gt 0) { 'Red' } else { 'Green' })
Write-Host "    Skipped: $Script:SkippedTests" -ForegroundColor Yellow
Write-Host '  ============================================' -ForegroundColor Cyan

if ($Script:FailedNames.Count -gt 0) {
    Write-Host ''
    Write-Host '  FAILURES:' -ForegroundColor Red
    foreach ($name in $Script:FailedNames) {
        Write-Host "    - $name" -ForegroundColor Red
    }
}

Write-Host ''
exit $Script:FailedTests
