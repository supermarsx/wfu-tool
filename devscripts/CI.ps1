<#
.SYNOPSIS
    Full CI pipeline: parse check, function inventory, run tests, package.
    Returns exit code 0 on success, non-zero on failure.
    Designed for CI/CD systems but also works locally.
#>
param(
    [switch]$SkipTests,
    [switch]$SkipPackage,
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$exitCode = 0

Write-Host ''
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host '  CI PIPELINE -- wfu-tool' -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host ''

# ================================================================
# Stage 1: Parse Check
# ================================================================
Write-Host '  [1/4] PARSE CHECK' -ForegroundColor Yellow
$scripts = Get-ChildItem $projectRoot -Filter '*.ps1' | Where-Object { $_.Name -ne 'CI.ps1' }
$parseErrors = 0
$totalLines = 0
$totalFuncs = 0

foreach ($script in $scripts) {
    $e = $null; $t = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$t, [ref]$e)
    $lines = (Get-Content $script.FullName).Count
    $funcs = ([regex]::Matches((Get-Content $script.FullName -Raw), '(?m)^function\s+')).Count
    $totalLines += $lines
    $totalFuncs += $funcs

    if ($e.Count -gt 0) {
        Write-Host "    FAIL: $($script.Name) ($($e.Count) errors)" -ForegroundColor Red
        foreach ($err in $e) { Write-Host "      Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red }
        $parseErrors += $e.Count
    } else {
        if ($Verbose) { Write-Host "    OK: $($script.Name) ($lines lines, $funcs functions)" -ForegroundColor DarkGray }
    }
}

# Check tests and devscripts too
foreach ($dir in @('tests', 'devscripts')) {
    $dirPath = Join-Path $projectRoot $dir
    if (Test-Path $dirPath) {
        Get-ChildItem $dirPath -Filter '*.ps1' | ForEach-Object {
            $e = $null; $t = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
            if ($e.Count -gt 0) {
                Write-Host "    FAIL: $dir\$($_.Name) ($($e.Count) errors)" -ForegroundColor Red
                $parseErrors += $e.Count
            }
        }
    }
}

if ($parseErrors -gt 0) {
    Write-Host "    FAILED: $parseErrors parse error(s)" -ForegroundColor Red
    $exitCode = 1
} else {
    Write-Host "    PASSED: All scripts parse clean ($totalLines lines, $totalFuncs functions)" -ForegroundColor Green
}

# ================================================================
# Stage 2: Encoding Check
# ================================================================
Write-Host ''
Write-Host '  [2/4] ENCODING CHECK' -ForegroundColor Yellow
$encodingErrors = 0
foreach ($script in $scripts) {
    $content = Get-Content $script.FullName -Raw
    $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]')
    if ($nonAscii.Count -gt 0) {
        Write-Host "    FAIL: $($script.Name) has $($nonAscii.Count) non-ASCII characters" -ForegroundColor Red
        $encodingErrors++
    }
}
if ($encodingErrors -gt 0) {
    Write-Host "    FAILED: $encodingErrors file(s) with encoding issues" -ForegroundColor Red
    $exitCode = 1
} else {
    Write-Host '    PASSED: All files are pure ASCII' -ForegroundColor Green
}

# ================================================================
# Stage 3: Tests
# ================================================================
Write-Host ''
if (-not $SkipTests) {
    Write-Host '  [3/4] TESTS' -ForegroundColor Yellow

    # Run the API test script (most comprehensive)
    $testScript = Join-Path $PSScriptRoot 'Run-ApiTests.ps1'
    if (Test-Path $testScript) {
        Write-Host '    Running API validation tests...' -ForegroundColor DarkGray
        & $testScript
        # Check the global counters from the test script
        if ($Script:f -gt 0) {
            Write-Host "    FAILED: $($Script:f) test failure(s)" -ForegroundColor Red
            $exitCode = 1
        }
    } else {
        Write-Host '    Run-ApiTests.ps1 not found -- skipping' -ForegroundColor Yellow
    }
} else {
    Write-Host '  [3/4] TESTS (skipped)' -ForegroundColor Yellow
}

# ================================================================
# Stage 4: Package
# ================================================================
Write-Host ''
if (-not $SkipPackage -and $exitCode -eq 0) {
    Write-Host '  [4/4] PACKAGE' -ForegroundColor Yellow
    $packageScript = Join-Path $PSScriptRoot 'Package.ps1'
    if (Test-Path $packageScript) {
        & $packageScript
    } else {
        Write-Host '    Package.ps1 not found -- skipping' -ForegroundColor Yellow
    }
} elseif ($exitCode -ne 0) {
    Write-Host '  [4/4] PACKAGE (skipped due to earlier failures)' -ForegroundColor Yellow
} else {
    Write-Host '  [4/4] PACKAGE (skipped)' -ForegroundColor Yellow
}

# ================================================================
# Summary
# ================================================================
Write-Host ''
Write-Host '  ============================================' -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host '  CI PASSED' -ForegroundColor Green
} else {
    Write-Host '  CI FAILED' -ForegroundColor Red
}
Write-Host "  Parse: $parseErrors errors | Encoding: $encodingErrors issues"
Write-Host "  Code: $totalLines lines, $totalFuncs functions"
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host ''

exit $exitCode
