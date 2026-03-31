<#
.SYNOPSIS
    Shows project statistics -- file sizes, line counts, function counts, test counts.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  PROJECT STATISTICS' -ForegroundColor Cyan
Write-Host '  ==================' -ForegroundColor Cyan
Write-Host ''

# Main scripts
Write-Host '  Main Scripts:' -ForegroundColor Yellow
$mainFiles = @('wfu-tool.ps1', 'launch-wfu-tool.ps1', 'resume-wfu-tool.ps1', 'launch-wfu-tool.bat')
$totalLines = 0
$totalSize = 0
foreach ($f in $mainFiles) {
    $path = Join-Path $projectRoot $f
    if (Test-Path $path) {
        $lines = (Get-Content $path).Count
        $size = (Get-Item $path).Length
        $totalLines += $lines
        $totalSize += $size
        $content = Get-Content $path -Raw
        $funcs = [regex]::Matches($content, '(?m)^function\s+').Count
        Write-Host "    $($f.PadRight(35)) $("$lines lines".PadRight(12)) $([math]::Round($size/1KB, 1)) KB   $funcs functions"
    }
}

# Tests
Write-Host ''
Write-Host '  Test Files:' -ForegroundColor Yellow
$testFiles = Get-ChildItem (Join-Path $projectRoot 'tests') -Filter '*.ps1' -ErrorAction SilentlyContinue
$testCount = 0
foreach ($tf in $testFiles) {
    $lines = (Get-Content $tf.FullName).Count
    $asserts = ([regex]::Matches((Get-Content $tf.FullName -Raw), 'Assert-')).Count
    $testCount += $asserts
    Write-Host "    $($tf.Name.PadRight(35)) $("$lines lines".PadRight(12)) $asserts assertions"
}

# Dev scripts
Write-Host ''
Write-Host '  Dev Scripts:' -ForegroundColor Yellow
$devFiles = Get-ChildItem (Join-Path $projectRoot 'devscripts') -Filter '*.ps1' -ErrorAction SilentlyContinue
$devFiles += Get-ChildItem (Join-Path $projectRoot 'devscripts') -Filter '*.bat' -ErrorAction SilentlyContinue
foreach ($df in $devFiles) {
    $lines = (Get-Content $df.FullName).Count
    Write-Host "    $($df.Name.PadRight(35)) $lines lines"
}

# Summary
Write-Host ''
Write-Host '  Summary:' -ForegroundColor Yellow
$allFuncs = 0
foreach ($f in $mainFiles) {
    $path = Join-Path $projectRoot $f
    if (Test-Path $path) { $allFuncs += [regex]::Matches((Get-Content $path -Raw), '(?m)^function\s+').Count }
}
Write-Host "    Total main script lines : $totalLines"
Write-Host "    Total main script size  : $([math]::Round($totalSize/1KB, 1)) KB"
Write-Host "    Total functions         : $allFuncs"
Write-Host "    Total test files        : $($testFiles.Count)"
Write-Host "    Total test assertions   : $testCount"
Write-Host "    Total dev scripts       : $($devFiles.Count)"
Write-Host ''
