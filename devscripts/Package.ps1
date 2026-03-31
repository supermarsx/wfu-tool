<#
.SYNOPSIS
    Packages the wfu-tool project into a distributable ZIP.
    Includes only the files needed for deployment -- no tests, devscripts, or source.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent
$version = '3.0'
$timestamp = Get-Date -Format 'yyyyMMdd'
$outName = "wfu-tool-v${version}-${timestamp}"
$outDir = Join-Path $projectRoot 'dist'
$stagingDir = Join-Path $outDir $outName
$zipPath = Join-Path $outDir "$outName.zip"

Write-Host ''
Write-Host "  PACKAGING $outName" -ForegroundColor Cyan
Write-Host ''

# Clean previous
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# Files to include
$includeFiles = @(
    'launch-wfu-tool.bat',
    'launch-wfu-tool.ps1',
    'wfu-tool.ps1',
    'resume-wfu-tool.ps1',
    'wfu-tool-windows-update.ps1'
)
$includeDirs = @(
    'modules'
)

foreach ($f in $includeFiles) {
    $src = Join-Path $projectRoot $f
    if (Test-Path $src) {
        Copy-Item $src $stagingDir
        Write-Host "  + $f" -ForegroundColor Green
    } else {
        Write-Host "  ! $f NOT FOUND" -ForegroundColor Red
    }
}

foreach ($dir in $includeDirs) {
    $srcDir = Join-Path $projectRoot $dir
    if (Test-Path $srcDir) {
        Copy-Item $srcDir (Join-Path $stagingDir $dir) -Recurse -Force
        Write-Host "  + $dir\\" -ForegroundColor Green
    } else {
        Write-Host "  ! $dir\\ NOT FOUND" -ForegroundColor Red
    }
}

# Parse check all packaged scripts
Write-Host ''
$errors = 0
Get-ChildItem $stagingDir -Filter '*.ps1' -Recurse | ForEach-Object {
    $e = $null; $t = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) {
        Write-Host "  PARSE FAIL: $($_.Name) ($($e.Count) errors)" -ForegroundColor Red
        $errors += $e.Count
    }
}

# Non-ASCII check
Get-ChildItem $stagingDir -Filter '*.ps1' -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]')
    if ($nonAscii.Count -gt 0) {
        Write-Host "  ENCODING WARN: $($_.Name) has $($nonAscii.Count) non-ASCII chars" -ForegroundColor Yellow
        $errors++
    }
}

if ($errors -gt 0) {
    Write-Host "  PACKAGING ABORTED: $errors issue(s) found." -ForegroundColor Red
    exit 1
}

# Create ZIP
Write-Host ''
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -Force
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB)
Write-Host "  Created: $zipPath ($zipSize KB)" -ForegroundColor Green

# Cleanup staging
Remove-Item $stagingDir -Recurse -Force

# Summary
$totalLines = 0
$totalFuncs = 0
foreach ($f in $includeFiles) {
    $src = Join-Path $projectRoot $f
    if (Test-Path $src) {
        $totalLines += (Get-Content $src).Count
        $totalFuncs += ([regex]::Matches((Get-Content $src -Raw), '(?m)^function\s+')).Count
    }
}
foreach ($dir in $includeDirs) {
    $srcDir = Join-Path $projectRoot $dir
    if (Test-Path $srcDir) {
        Get-ChildItem $srcDir -Filter '*.ps1' -Recurse | ForEach-Object {
            $totalLines += (Get-Content $_.FullName).Count
            $totalFuncs += ([regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^function\s+')).Count
        }
    }
}

Write-Host ''
Write-Host '  Package contents:' -ForegroundColor Cyan
Write-Host "    Files:     $($includeFiles.Count)"
Write-Host "    Dirs:      $($includeDirs.Count)"
Write-Host "    Lines:     $totalLines"
Write-Host "    Functions: $totalFuncs"
Write-Host "    Size:      $zipSize KB"
Write-Host ''
