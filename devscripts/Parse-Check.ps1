<#
.SYNOPSIS
    Quick syntax check for all PS1 scripts in the project.
    Reports parse errors, non-ASCII characters, and function counts.
#>
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '  SYNTAX CHECK' -ForegroundColor Cyan
Write-Host '  ============' -ForegroundColor Cyan
Write-Host ''

$totalErrors = 0
$scripts = Get-ChildItem $projectRoot -Filter '*.ps1' -Recurse | Where-Object { $_.FullName -notmatch 'tests\\' }

foreach ($script in $scripts) {
    $errors = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)

    $lines = (Get-Content $script.FullName).Count
    $content = Get-Content $script.FullName -Raw
    $funcs = [regex]::Matches($content, '(?m)^function\s+(\S+)').Count
    $nonAscii = [regex]::Matches($content, '[^\x00-\x7F]').Count

    $status = if ($errors.Count -eq 0 -and $nonAscii -eq 0) { 'OK' } else { 'FAIL' }
    $color = if ($status -eq 'OK') { 'Green' } else { 'Red' }

    $rel = $script.FullName.Replace($projectRoot, '').TrimStart('\')
    Write-Host "  [$status] " -ForegroundColor $color -NoNewline
    Write-Host "$rel" -NoNewline
    Write-Host " ($lines lines, $funcs functions, $($errors.Count) errors, $nonAscii non-ASCII)" -ForegroundColor DarkGray

    foreach ($err in $errors) {
        Write-Host "        Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        $totalErrors++
    }
}

Write-Host ''
if ($totalErrors -eq 0) {
    Write-Host '  All scripts parse clean.' -ForegroundColor Green
}
else {
    Write-Host "  $totalErrors total error(s) found." -ForegroundColor Red
}
Write-Host ''
